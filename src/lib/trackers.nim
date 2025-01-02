import nanoid
import std/[uri, tables, strutils, sequtils]
import bencode

type
  AnnounceEvent* = enum
    aeNone = "none"
    aeStarted = "started"
    aeStopped = "stopped"
    aeCompleted = "completed"

  TrackerRequest* = object
    infoHash*: string
    peerId*: string
    port*: int
    uploaded*: int
    downloaded*: int
    left*: int64
    event*: AnnounceEvent
    compact*: bool
    numWant*: int

  Peer* = object
    ip*: string
    port*: uint16
    peerId*: string

  TrackerResponse* = object
    interval*: int
    minInterval*: int
    trackerId*: string
    complete*: int
    incomplete*: int
    peers*: seq[Peer]
    warning*: string
    failureReason*: string

proc newTrackerRequest*(info_hash: string): TrackerRequest =
  let
    identifier = "ttc_"
    alphabets = "abcdefghijklmnopqrstuvwxyz1234567890"
    s = 16

  return TrackerRequest(
    infoHash: info_hash,
    peerId: identifier & generate(alphabets, s),
    port: 6881,
    uploaded: 0,
    downloaded: 0,
    left: 0,
    event: aeStarted,
    compact: true,
    numWant: 50,
  )

proc encodeInfoHash(hexHash: string): string =
  # hex string to bytes
  var bytes = newString(hexHash.len div 2)
  for i in countup(0, hexHash.len - 2, 2):
    bytes[i div 2] = chr(parseHexInt(hexHash[i .. i + 1]))

  # URL encode the bytes
  result = newString(bytes.len * 3)
  var j = 0
  for b in bytes:
    result[j] = '%'
    result[j + 1 .. j + 2] = toHex(ord(b), 2)
    j += 3

proc buildAnnounceUrl*(tracker: string, req: TrackerRequest): string =
  var url = parseUri(tracker)

  var params = {
    "info_hash": req.infoHash.encodeInfoHash(),
    "peer_id": req.peerId,
    "port": $req.port,
    # "uploaded": $req.uploaded,
    "downloaded": $req.downloaded,
    "left": $req.left,
    "compact": if req.compact: "1" else: "0", # "numwant": $req.numWant
  }.toTable

  if req.event != aeNone:
    params["event"] = $req.event

  var queryParams: seq[(string, string)] = @[]
  for key, value in params.pairs:
    queryParams.add((key, value))

  url.query = queryParams.mapIt(it[0] & "=" & it[1]).join("&")
  return $url

proc decodePeers(peerData: string): seq[Peer] =
  result = @[]
  # Each peer is 6 bytes: 4 for IP + 2 for port
  for i in countup(0, peerData.len - 6, 6):
    var peer: Peer
    let ip1 = uint8(peerData[i + 0])
    let ip2 = uint8(peerData[i + 1])
    let ip3 = uint8(peerData[i + 2])
    let ip4 = uint8(peerData[i + 3])
    peer.ip = $ip1 & "." & $ip2 & "." & $ip3 & "." & $ip4

    # Get port (2 bytes in network byte order / big endian)
    peer.port = (uint16(peerData[i + 4]) shl 8) or uint16(peerData[i + 5])

    result.add(peer)

proc parseResponse*(response: string): TrackerResponse =
  let resp = bdecode(response)

  result = TrackerResponse(
    interval: 0,
    minInterval: 0,
    trackerId: "",
    complete: 0,
    incomplete: 0,
    peers: @[],
    warning: "",
    failureReason: "",
  )

  for key, val in resp.dictVal:
    case key
    of "complete":
      result.complete = val.intVal
    of "incomplete":
      result.incomplete = val.intVal
    of "interval":
      result.interval = val.intVal
    of "min interval":
      result.minInterval = val.intVal
    of "peers":
      result.peers = decodePeers(val.strVal)
    else:
      discard
