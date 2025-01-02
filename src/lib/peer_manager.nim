import trackers, utils, message
import std/[sequtils, asyncdispatch, strutils, asyncnet, bitops]

type
  HandShake* = object
    pStr*: string = "BitTorrent Protocol"
    infoHash*: array[20, byte]
    peerId*: array[20, byte]

  Torrent* = object
    peers*: seq[Peer]
    peerId*: array[20, byte]
    infoHash*: array[20, byte]
    pieceHashes*: seq[array[20, byte]]
    pieceLength*: int
    length*: int
    name*: string

proc handshakeRequest(obj: Handshake): seq[byte] =
  # 19 (pstr length) + Protocl identifier + 8 (reserved) + 20 (infoHash) + 20 (peerId)
  let totalSize = obj.pStr.len + 49
  result = newSeq[byte](totalSize)
  var currentPos = 0

  # pstr length
  result[currentPos] = byte(obj.pstr.len)
  currentPos.inc

  # pstr
  for i, c in obj.pstr:
    result[currentPos + i] = byte(c)
  currentPos.inc(obj.pstr.len)

  # 8 reserved bytes
  for i in 0 .. 7:
    result[currentPos + i] = 0'u8
  currentPos.inc(8)

  # infoHash
  for i, b in obj.infoHash:
    result[currentPos + i] = b
  currentPos.inc(20)

  # peerId
  for i, b in obj.peerId:
    result[currentPos + i] = b

proc verify(response: seq[byte], expected: array[20, byte]): bool =
  if response.len != 68:
    return false

  if response[0] != 19:
    echo "Invalid protocol string length: " & $response[0] & " (expected 19)"
    return false

  # Check protocol string
  let protocol = "BitTorrent Protocol"
  let receivedProtocol = response[1 .. 19].mapIt(char(it)).join("")
  if receivedProtocol != protocol:
    echo "Protocol string not same"
    return false

  if response[28 .. 47] != expected:
    echo "info hash not same"
    return false

  return true

proc performHandshake*(s: AsyncSocket, peer: Peer, torr: Torrent): Future[bool] {.async.} =
  await s.connect(peer.ip, Port(peer.port))

  let handshake = HandShake(infoHash: torr.infoHash, peerId: torr.peerId)
  let req = handshake.handshakeRequest()

  await s.send($req)

  let response = await s.recv(68)

  if not verify(response.toByteSeq, torr.infoHash):
    echo "handshake failed"
    return false

  return true


proc hasPiece*(bitfield: seq[byte], index: int): bool =
  let byteIndex = index div 8
  let offset = index mod 8
  if byteIndex < 0 or byteIndex >= bitfield.len:
    return false
  return ((bitfield[byteIndex] shr (7 - offset)) and 1) != 0


proc setPiece*(bitfield: var seq[byte], index: int) =
  let byteIndex = index div 8
  let offset = index mod 8
  if byteIndex < 0 or byteIndex >= bitfield.len:
    return
  bitfield[byteIndex] = bitfield[byteIndex] or byte(1 shl (7 - offset))



