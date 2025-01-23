import std/[asyncnet]

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
    id: PeerActions
    payload: seq[byte]

proc sendRequest(s: AsyncSocket, idx, begin, length: int) = discard
proc sendChoke(s: AsyncSocket) = discard
proc sendUnchoke(s: AsyncSocket) = discard
proc sendInterested(s: AsyncSocket) = discard
proc sendNotInterested(s: AsyncSocket) = discard
proc sendHave(s: AsyncSocket, idx: int) = discard