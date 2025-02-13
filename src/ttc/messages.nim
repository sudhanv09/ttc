import std/[asyncnet, asyncdispatch, endians]

type
  PeerActions* = enum
    pChoke = 0
    pUnchoke = 1
    pInterested = 2
    pUninterested = 3
    pHave = 4
    pBitfield = 5
    pRequest = 6
    pPiece = 7
    pCancel = 8

  Message* = object
    Id*: PeerActions
    Payload*: seq[byte]


proc serialize(msg: Message): seq[byte] = 
  let length = msg.Payload.len + 1 # 1 for id
  var data = newSeq[byte](4 + length)

  # payload length
  for i in 0..3:
    data[i] = byte((length shr (8 * (3 - i))) and 0xFF)

  # Action
  data[4] = msg.Id.byte

  # Payload
  for i, b in msg.Payload:
    data[i+5] = b

  return data

proc sendRequest*(s: AsyncSocket, idx, begin, length: int) {.async.} = 
  var data = newSeq[byte](12)
  
  bigEndian32(addr data[0], addr idx)
  bigEndian32(addr data[4], addr begin)
  bigEndian32(addr data[8], addr length)

  let msg = Message(Id: pRequest, Payload: data).serialize()
  await s.send(addr msg[0], msg.len)


proc sendKeepAlive(s: AsyncSocket) {.async.} = 
  var msg = newSeq[byte](4)
  for i in 0..3:
    msg[i] = 0.byte
    
  await s.send(addr msg[0], msg.len)

proc sendChoke*(s: AsyncSocket) {.async.} = 
  let msg = Message(Id: pChoke).serialize()
  await s.send(addr msg[0], msg.len)
  
proc sendUnchoke*(s: AsyncSocket) {.async.} = 
  let msg = Message(Id: pUnchoke).serialize()
  await s.send(addr msg[0], msg.len)

proc sendInterested*(s: AsyncSocket) {.async.} = 
  let msg = Message(Id: pInterested).serialize()
  await s.send(addr msg[0], msg.len)

proc sendNotInterested*(s: AsyncSocket) {.async.} = 
  let msg = Message(Id: pUninterested).serialize()
  await s.send(addr msg[0], msg.len)

proc sendHave*(s: AsyncSocket, idx: int) {.async.} = 
  let msg = Message(Id: pHave).serialize()
  await s.send(addr msg[0], msg.len)