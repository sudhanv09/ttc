import utils, peers
import std/[tables, asyncnet, asyncdispatch, strutils, math]
import ../bencode/core

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

  FileDict* = object
    Length*: int
    Path*: string

  MetaDataInfo* = object
    MsgType*: MessageType
    PieceIndex*: int
    TotalSize*: int

  MetaDataFiles* = object
    Files*: seq[FileDict]
    Name*: string
    PieceLength*: int
    PieceHashes*: seq[seq[byte]]

  TorrentMetadata* = object
    Info*: MetaDataInfo
    File*: MetaDataFiles

  PeerData* = object
    Conn*: AsyncSocket
    Peer*: TPeers
    Piece*: seq[byte] 
    Meta*: TorrentMetadata

const METADATA_PIECE_SIZE* = 16384

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

proc create_extend_msg(req_id: int, payload: BencodeObj): seq[byte] = 
  let serialize = bEncode(payload)

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
    let bcString = bDecode(msg_str)
    for key, item in bcString.d.pairs:
      case key:
        of "complete_ago":
          extended.Complete = item.i
        of "metadata_size":
          extended.Metadata = item.i.int32
        of "m":
            for k, val in item.d.pairs:
              case k:
                of "lt_donthave":
                  extended.M.LtDontHave = val.i
                of "share_mode":
                  extended.M.ShareMode = val.i
                of "upload_only":
                  extended.M.UploadOnly = val.i
                of "ut_holepunch":
                  extended.M.UtHolepunch = val.i
                of "ut_metadata":
                  extended.M.UtMeta = val.i
                of "ut_pex":
                  extended.M.UtPex = val.i

    return extended
  except Exception as _:
    discard

proc send_verify_handshake*(s: AsyncSocket, msg: Handshake): Future[bool] {.async.} = 
  try:
    let hmsg: array[68, byte] = create_handshake_msg(msg, true)

    let payload = Bencode({
      "m": Bencode({
        "ut_metadata": Bencode(2),
        "metadata_size": Bencode(0)
      })
    })
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

proc parse_metainfo(arr: seq[byte]): MetaDataInfo = 
  let msg_str = arr.fromBytes()
  var res: MetaDataInfo

  try:
    let bcString = bDecode(msg_str)
    for key, item in bcString.d.pairs:
      case key:
      of "msg_type":
        res.MsgType = MessageType(item.i)
      of "piece":
        res.PieceIndex = item.i
      of "total_size":
        res.TotalSize = item.i
      else:
        discard

    return res
  except Exception as _:
    discard

# helper functions
proc parseFileDict(node: BencodeObj): FileDict =
  result = FileDict()
  for key, val in node.d.pairs:
    case key
    of "length":
      if val.kind == bkInt:
        result.Length = val.i
    of "path":
      if val.kind == bkList:
        for item in val.l:
            result.Path = item.s
    else:
      discard

proc parseFile(node: BencodeObj): seq[FileDict] = 
    result = @[]
    if node.kind == bkList:
        for item in node.l:
            result.add(parseFileDict(item))

proc split_piece_hashes(item: seq[byte]): seq[seq[byte]] = 
  if item.len mod 20 != 0:
    echo "Malformed piece. got: ", item.len
    return

  let num_hashes = item.len div 20
  var hashes = newSeq[seq[byte]](num_hashes)

  for i in 0..<num_hashes:
    hashes[i] = newSeq[byte](20)
    copyMem(addr hashes[i][0], unsafeAddr item[i*20], 20)
  
  return hashes

proc parse_metafile(arr: seq[byte]): MetaDataFiles = 
  let msg_str = arr.fromBytes()

  var res: MetaDataFiles
  try:
    let bcString = bDecode(msg_str)
    for key, item in bcString.d.pairs:
      case key:
      of "name":
        res.Name = item.s
      of "piece length":
        res.PieceLength = item.i
      of "files":
        res.Files = parseFile(item)
      of "length":
        var fd = FileDict()
        fd.Length = item.i
        fd.Path = res.Name
        res.Files.add(fd)
      of "pieces":
        res.PieceHashes = split_piece_hashes(item.s.toBytes())
      else:
        discard

    return res
  except Exception as e:
    echo "Failed to parse message ", e.msg

proc request_metadata*(s: AsyncSocket, ut_id, piece: int): Future[TorrentMetadata] {.async.} = 
  var data_acc: seq[byte] = @[]
  var total_size = 0
  var pieces_required = 0.0
  var curr_piece = piece
  var meta_info: MetaDataInfo

  while true:
    let payload = Bencode({
      "msg_type": Bencode(ord(Request)),
      "piece": Bencode(curr_piece)
    })
    let msg = create_extend_msg(ut_id, payload)

    await s.send(addr msg[0], msg.len)
    let recvMsg = await getMessage(s)

    if curr_piece == 0:
      meta_info = parse_metainfo(recvMsg[2..46])
      total_size = meta_info.TotalSize
      pieces_required = ceil(total_size / METADATA_PIECE_SIZE)
    
    let piece_data = recvMsg[47..^1]
    data_acc.add(piece_data)

    curr_piece += 1
    if data_acc.len >= total_size:
      break
  

  let file_info = parse_metafile(data_acc)
  return TorrentMetadata(Info: meta_info, File: file_info)


proc connect_peer(msg: HandShake, peer: TPeers): Future[PeerData] {.async.} = 
  try:
    var s = await asyncnet.dial(peer.Ip, Port(peer.Port))
    
    if not await send_verify_handshake(s, msg):
      s.close()
      # echo "handshake failed"
      return PeerData()

    var extMsg = await s.get_message()
    let res = extMsg.parse_extend_message()
    let bits = await s.get_message()

    var meta: TorrentMetadata
    if res.M.UtMeta != 0:
      meta = await s.request_metadata(res.M.UtMeta, 0)

    return PeerData(Conn: s, Peer: peer, Piece: bits, Meta: meta)

  except Exception as _:
    return PeerData()

proc contact*(id, hash: string, peers: seq[TPeers]): Future[seq[PeerData]] {.async.} =
  var futures: seq[Future[PeerData]] = @[]
  
  let hobj = HandShake(
    Identifier: "BitTorrent protocol",
    InfoHash: hash.hexStringToBytes(20),
    PeerId: id.toBytesArray(20)
    )

  # Start all peer connections concurrently
  for peer in peers:
    futures.add(connect_peer(hobj, peer))

  # Wait up to 30 seconds, collecting results as they complete
  let allResults = await awaitWithTimeout(futures, 30_000)
  
  # Filter to only include successful connections
  var results: seq[PeerData] = @[]
  for peerData in allResults:
    if not peerData.Conn.isNil:
      results.add(peerData)
  
  echo "Collected ", results.len, " successful peer connections"
  return results


