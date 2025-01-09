import utils, peers
import std/[tables, asyncnet, asyncdispatch]
import bencode

type
  HandShake = object
    Identifier: string
    InfoHash: array[20, byte]
    PeerId: array[20, byte]
  
proc init_handshake(handshake: HandShake, extend: bool = false): seq[byte] = 
  var msg = newSeq[byte](68)
  var currPos = 0

  # pstr len
  msg[currPos] = 0x19
  currPos.inc

  # protocol identifier
  let identifierBytes = handshake.Identifier.toBytes
  for i, b in identifierBytes:
    msg[currPos + i] = b
  currPos.inc handshake.Identifier.len

  # reserved
  for i in 0..8:
    msg[currPos + i] = 0'u8
  if extend:
    msg[currPos + 5] = 0x10
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
  let payload = {"m": {"ut_metadata": "2", "metadata_size": "0"}}.toTable
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

proc connect_peer(msg: HandShake, peer: TPeers): Future[string] {.async.} = 
  try:
    var s = newAsyncSocket()
    await s.connect(peer.Ip, Port(peer.Port))

    let payload = init_handshake(msg)
    await s.send($payload)

    let response = await s.recv(68)
    echo response
    if response.len != 68:
      s.close()
      echo "error. response not as expected"

    let ext_msg = extend_handshake()
    await s.send($ext_msg)

    let init_resp = await s.recv(4)
    if init_resp.len != 4:
      s.close()
      return ""

    let msgLength = (
      (ext_msg[0].uint32 shl 24) or
      (ext_msg[1].uint32 shl 16) or 
      (ext_msg[2].uint32 shl 8) or
      ext_msg[3].uint32
    )
    
    # Read extension message
    let extResponse = await s.recv(msgLength.int)
    echo extResponse
    s.close()
    return extResponse
  
  except Exception as e:
    echo "unable to connect to peer: ", peer.Ip

proc contact*(id, hash: string, peers: seq[TPeers]): Future[seq[string]] {.async.} = 
  var futures: seq[Future[string]] = @[]
  let hobj = HandShake(
    Identifier: "BitTorrent protocol",
    InfoHash: hash.toBytesArray(20),
    PeerId: id.toBytesArray(20)
    )

  for peer in peers:
    futures.add(connect_peer(hobj, peer))

  return await all(futures)