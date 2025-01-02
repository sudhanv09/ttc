import trackers
import std/[sequtils, strutils]

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

    PeerStatus* = enum
        choke = 0
        unchoke = 1
        interested = 2
        uninterested = 3
        have = 4
        bitfield = 5
        request = 6
        piece = 7
        cancel = 8


proc initHandshake*(obj: Handshake): seq[byte] =
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
  for i in 0..7:
    result[currentPos + i] = 0'u8
  currentPos.inc(8)

  # infoHash
  for i, b in obj.infoHash:
    result[currentPos + i] = b
  currentPos.inc(20)

  # peerId
  for i, b in obj.peerId:
    result[currentPos + i] = b

proc verifyMessage*(response: seq[byte], expected: string): bool = 
  if response.len != 68:
    return false

  if response[0] != 19:
        echo "Invalid protocol string length: " & $response[0] & " (expected 19)"
        return false
    
  # Check protocol string
  let protocol = "BitTorrent Protocol"
  let receivedProtocol = response[1..19].mapIt(char(it)).join("")
  if receivedProtocol != protocol:
      echo "Protocol string not same"
      return false
   
  # Check info hash
  let receivedInfoHash = response[28..47].mapIt(it.toHex(2)).join("").toUpperAscii()

  if receivedInfoHash != expected:
      echo "info hash not same"
      return false
  
  return true


