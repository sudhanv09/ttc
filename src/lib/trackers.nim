import nanoid
import std/[uri, tables, strutils]

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
        s = 10

    return TrackerRequest(
        infoHash: info_hash,
        peerId: identifier & generate(alphabets, s),
        port: 6881,
        uploaded: 0,
        downloaded: 0,
        left: 0,
        event: aeStarted,
        compact: true,
        numWant: 50
    ) 

proc buildAnnounceUrl*(tracker: string, req: TrackerRequest): string =
    var url = parseUri(tracker)
    var params = {
        "info_hash": parseHexStr(req.infoHash),
        "peer_id": req.peerId,
        "port": $req.port,
        "uploaded": $req.uploaded,
        "downloaded": $req.downloaded,
        "left": $req.left,
        "compact": if req.compact: "1" else: "0",
        "numwant": $req.numWant
    }.toTable

    if req.event != aeNone:
        params["event"] = $req.event

    var queryParams: seq[(string, string)] = @[]
    for key, value in params.pairs:
        queryParams.add((key, value))

    url.query = encodeQuery(queryParams)
    return $url

