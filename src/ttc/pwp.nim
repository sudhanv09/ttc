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
