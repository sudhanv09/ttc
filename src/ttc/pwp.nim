import utils, peers, messages
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

  PeerData* = object
    PeerIp: TPeers
    Piece*: seq[byte] 


proc init_handshake(handshake: HandShake, extend: bool = false): array[68, byte] = 
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


proc extend_handshake(): seq[byte] = 
  let payload = {"m": {"ut_metadata": 2, "metadata_size": 0}}.toTable
  let serialize = bencode(payload)

  var ext_msg = newSeq[byte]()
  ext_msg.add(20'u8) # extended message ID
  ext_msg.add(0'u8) # handshake id
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

proc send_verify_handshake*(s: AsyncSocket, msg: Handshake, peer: TPeers): Future[bool] {.async.} = 
  try:

    var s = await asyncnet.dial(peer.Ip, Port(peer.Port))
    defer: s.close()

    let hmsg: array[68, byte] = init_handshake(msg, true)
    let extend: seq[byte] = extend_handshake()
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

proc request_metadata*(s: AsyncSocket) {.async.} = discard

proc get_piece(idx: int) = discard


proc request_bitfields*(s: AsyncSocket): Future[PeerData] {.async.} = 
  var bitLen: array[4, byte]
  discard await s.recvInto(addr bitLen[0], 4)

  var bitfield = newSeq[byte](bitLen.bToInt())
  discard await s.recvInto(addr bitfield[0], bitLen.bToInt())


proc connect_peer(msg: HandShake, peer: TPeers): Future[string] {.async.} = 
  try:
    var s = await asyncnet.dial(peer.Ip, Port(peer.Port))
    defer: s.close()

    

    var extlen: array[4, byte]
    discard await s.recvInto(addr extlen[0], 4)

    var extMsg = newSeq[byte](extlen.bToInt())
    discard await s.recvInto(addr extMsg[0], extlen.bToInt())

    echo "msg: ", extMsg.parse_extend_message()

    var bitLen: array[4, byte]
    discard await s.recvInto(addr bitLen[0], 4)

    var bitfield = newSeq[byte](bitLen.bToInt())
    discard await s.recvInto(addr bitfield[0], bitLen.bToInt())

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