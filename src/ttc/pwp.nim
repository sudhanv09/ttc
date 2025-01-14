import utils, peers, messages
import std/[tables, asyncnet, asyncdispatch, strutils]
import bencode

type
  HandShake = object
    Identifier: string
    InfoHash: array[20, byte]
    PeerId: array[20, byte]


  
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

proc parse_extend_message(arr: seq[byte]) = discard

proc connect_peer(msg: HandShake, peer: TPeers): Future[string] {.async.} = 
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

    var resp: array[600, byte]
    discard await s.recvInto(addr resp[0], 600)
    
    if resp[28..47] != msg.InfoHash:
      echo "hash mismatch"
      s.close()
      return ""

    let ext_len = resp[68..71][3]

    echo "ext: ", resp[72..ext_len]

    echo "bitfield: ", resp[284..^1], "\n"

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