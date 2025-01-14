
type
  PeerActions = enum
    pChoke = 0
    pUnchoke = 1
    pInterested = 2
    pUninterested = 3
    pHave = 4
    pBitfield = 5
    pRequest = 6
    pPiece = 7
    pCancel = 8

  Message = object
    id: int32
    payload: seq[byte]

