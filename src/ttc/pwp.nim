import utils, peers
import std/[tables, asyncnet, asyncdispatch, strutils]
import bencode

type
  HandShake = object
    Identifier: string
    InfoHash: array[20, byte]
    PeerId: array[20, byte]

  ExtendResponse = object
    Complete*: int
    M*: MDict
    Metadata*: int32

  MDict = object
    LtDontHave*: int
    ShareMode*: int
    UploadOnly*: int
    UtHolepunch*: int
    UtMeta*: int
    UtPex*: int

  MessageType = enum
    Request = 0
    Data = 1
    Reject = 2

  MetaInfoData* = object
    MsgType*: MessageType
    Piece*: int
    TotalSize*: int
    Files*: seq[FileDict]
    Name*: string
    PieceLen*: int
    SHAPieces*: seq[byte]

  FileDict* = object
    Length*: int
    Path*: string

  PeerData* = object
    PeerIp: TPeers
    Piece*: seq[byte] 


proc get_message(s: AsyncSocket): Future[seq[byte]] {.async.} = 
  var msglen: array[4, byte]
  discard await s.recvInto(addr msgLen[0], 4)

  var msg = newSeq[byte](msgLen.bToInt())
  discard await s.recvInto(addr msg[0], msgLen.bToInt())

  return msg

proc create_handshake_msg(handshake: HandShake, extend: bool = false): array[68, byte] = 
  var msg: array[68, byte]
  var currPos = 0

  # pstr len
  msg[currPos] = 19'u8
  currPos.inc

  # protocol identifier
  let identifierBytes = handshake.Identifier.toBytes
  for i, b in identifierBytes:
    msg[currPos + i] = b
  currPos.inc handshake.Identifier.len

  # reserved
  for i in 0..7:
    msg[currPos + i] = if i == 5 and extend: 20'u8 else: 0'u8
  currPos.inc 8

  # hash
  for i, b in handshake.InfoHash:
    msg[currPos + i] = b
  currPos.inc 20

  for i, b in handshake.PeerId:
    msg[currPos + i] = b
  currPos.inc 20

  assert currPos == 68
  return msg

proc create_extend_msg(req_id: int, payload: Table): seq[byte] = 
  let serialize = bencode(payload)

  var ext_msg = newSeq[byte]()
  ext_msg.add(20'u8) # extended message ID
  ext_msg.add(req_id.uint8) # handshake id
  ext_msg.add(serialize.toBytes)

  let msg_len = ext_msg.len.uint32
  
  var msg = newSeq[byte](4)
  msg[0] = byte((msg_len shr 24) and 0xff)
  msg[1] = byte((msg_len shr 16) and 0xff)
  msg[2] = byte((msg_len shr 8) and 0xff)
  msg[3] = byte(msg_len and 0xff)
  msg.add(ext_msg)

  return msg

proc parse_extend_message(arr: seq[byte]): ExtendResponse = 
  let msg_str = arr[2..^1].fromBytes()
  var extended: ExtendResponse

  try:
    let bcString = bdecode(msg_str)
    for key, item in bcString.dictVal.pairs:
      case key:
        of "complete_ago":
          extended.Complete = item.intVal
        of "metadata_size":
          extended.Metadata = item.intVal.int32
        of "m":
            for k, i in item.dictVal.pairs:
              case k:
                of "lt_donthave":
                  extended.M.LtDontHave = i.intVal
                of "share_mode":
                  extended.M.ShareMode = i.intVal
                of "upload_only":
                  extended.M.UploadOnly = i.intVal
                of "ut_holepunch":
                  extended.M.UtHolepunch = i.intVal
                of "ut_metadata":
                  extended.M.UtMeta = i.intVal
                of "ut_pex":
                  extended.M.UtPex = i.intVal

    return extended
  except Exception as _:
    discard

proc send_verify_handshake*(s: AsyncSocket, msg: Handshake): Future[bool] {.async.} = 
  try:
    let hmsg: array[68, byte] = create_handshake_msg(msg, true)

    let payload = {"m": {"ut_metadata": 2, "metadata_size": 0}}.toTable
    let extend: seq[byte] = create_extend_msg(0, payload)
    let msglen = hmsg.len + extend.len

    var combined = newSeq[byte](msglen)
    
    for i, b in hmsg:
      combined[i] = b
    for i, b in extend:
      combined[hmsg.len + i] = b

    await s.send(addr combined[0], msglen)

    var resp: array[68, byte]
    discard await s.recvInto(addr resp[0], 68)

    if resp[28..47] != msg.InfoHash:
      s.close()
      return false

    return true

  except Exception as _: discard

proc parse_metadata(arr: seq[byte]): MetaInfoData = 
  if not arr[0] == 20'u8:
    echo "Not metadata"
    return MetaInfoData()

  let msg_str = arr[2..^1].fromBytes().replace(" ", "")
  var res: MetaInfoData

  try:
    let bcString = bdecode(msg_str)
    echo bcString
    for key, item in bcString.dictVal.pairs:
      case key:
      of "msg_type":
        res.MsgType = MessageType(item.intVal)
      of "piece":
        res.Piece = item.intVal
      of "total_size":
        res.TotalSize = item.intVal
      of "name":
        res.Name = item.strVal
      of "piece length":
        res.PieceLen = item.intVal
      of "files":
        res.Files = @[]
        for file in item.listVal:
          var fileDict: FileDict
          for fileKey, fileItem in file.dictVal.pairs:
            case fileKey:
            of "length":
              fileDict.Length = fileItem.intVal
            of "path":
              fileDict.Path = fileItem.listVal[0].strVal
          res.Files.add(fileDict)
      of "pieces":
        res.SHAPieces = cast[seq[byte]](item.strVal)
      else:
        discard

    return res
  except Exception as _:
    discard

proc request_metadata*(s: AsyncSocket, ut_id, piece: int) {.async.} = 
  let payload = {"msg_type": 0, "piece": piece }.toTable
  let msg = create_extend_msg(ut_id, payload)

  await s.send(addr msg[0], msg.len)

  let recvMsg = await getMessage(s)
  discard recvMsg.parse_metadata()

proc get_piece(idx: int) = discard

proc request_bitfields*(s: AsyncSocket): Future[PeerData] {.async.} = 
  let bits = await get_message(s)

proc connect_peer(msg: HandShake, peer: TPeers): Future[string] {.async.} = 
  try:
    var s = await asyncnet.dial(peer.Ip, Port(peer.Port))
    defer: s.close()

    if not await send_verify_handshake(s, msg):
      s.close()
      echo "handshake failed"

    var extMsg = await s.get_message()
    let res = extMsg.parse_extend_message()
    discard await s.request_bitfields()

    if res.M.UtMeta != 0:
      echo " requesting first piece"
      await s.request_metadata(res.M.UtMeta, 0)

  except Exception as _:
    discard

proc contact*(id, hash: string, peers: seq[TPeers]): Future[seq[string]] {.async.} = 
  var futures: seq[Future[string]] = @[]
  let hobj = HandShake(
    Identifier: "BitTorrent protocol",
    InfoHash: hash.hexStringToBytes(20),
    PeerId: id.toBytesArray(20)
    )

  for peer in peers:
    futures.add(connect_peer(hobj, peer))

  return await all(futures)