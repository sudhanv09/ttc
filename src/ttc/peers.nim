import magnet
import std/[uri, strutils, asyncdispatch, httpclient, tables]
import bencode

type
  TrackerReq* = object
    InfoHash*: string
    PeerId*: string
    Port*: int = 6881
    Uploaded: int = 0
    Downloaded: int = 0
    Left: int = 0 
    Compact: bool = true
    Event*: AeEvent

  TrackerResp = object
    Failure: string
    Warning: string
    Interval: int
    MinInterval: int
    Complete: int
    Incomplete: int
    Peers: seq[Peers]

  Peers* = object
    PeerId: string
    Ip: string
    Port: int

  AeEvent = enum
    Started
    Stopped
    Completed
   


proc build_announce_url(id, info_hash, trackerUrl: string): string =
  var uri = parseUri(trackerUrl)

  let hashBytes = info_hash.parseHexStr
  let queries = encodeQuery({
    "info_hash": hashBytes,
    "peer_id": id,
    "port": "6881",
    "uploaded": "0",
    "downloaded": "0",
    "compact": "1",
    "left": "0",
    "event": "started"
  })

  uri.query = queries
  return $uri

proc decode_peers(peer_data: string): Peers =
  result.Ip = $ord(peer_data[0]).uint8 & "." &
              $ord(peer_data[1]).uint8 & "." &
              $ord(peer_data[2]).uint8 & "." &
              $ord(peer_data[3]).uint8
  
  result.Port = (ord(peer_data[4]).int shl 8) or
                ord(peer_data[5]).int

proc parse_peers(peer_str: string): seq[Peers] =
  var offset = 0
  result = @[]
  
  while offset < peer_str.len:
    if offset + 6 <= peer_str.len:
      let peer_data = peer_str[offset..offset+5]
      result.add(decode_peers(peer_data))
    offset += 6

proc parse_response(resp: string): TrackerResp = 
  let bcString = bdecode(resp)
  var tracker = TrackerResp()
  
  for key, item in bcString.dictVal.pairs:
    case key:
      of "interval":
        tracker.Interval = item.intVal
      of "min interval":
        tracker.MinInterval = item.intVal
      of "complete":
        tracker.Complete = item.intVal
      of "incomplete":
        tracker.Incomplete = item.intVal
      of "peers":
          let peers = parse_peers(item.strVal)
          if peers.len > 0:
            result.Peers = peers

    return tracker
    
proc send_request(url: string): Future[TrackerResp] {.async.} = 
  try:
    var client = newAsyncHttpClient()
    
    let req = await client.get(url)
    let body = await req.body

    if not body.startsWith("<!D"):
      return body.parse_response
  except Exception as e:
    echo "trouble sending request"

proc connect_trackers*(id: string, magnet: Magnet): Future[seq[TrackerResp]] {.async.} =
  var futures: seq[Future[TrackerResp]] = @[]

  for tracker in magnet.Trackers:
    echo "trying: ", tracker
    let url = build_announce_url(id, magnet.InfoHash, tracker)
    futures.add send_request(url)

  return await all(futures)

proc scrape_tracker(tracker, info_hash: string): Future[seq[string]] {.async.} = 
  var uri = parseUri(tracker)
  uri.path = "scrape"

  let hashBytes = info_hash.parseHexStr
  let queries = encodeQuery({
    "info_hash": hashBytes,
  })

  uri.query = queries
  
  var futures: seq[Future[string]] = @[]
  try:
    var client = newAsyncHttpClient()
    var req = await client.get(uri)

    echo await req.body
    futures.add(req.body)
  except Exception:
    echo "unable to scrape"

  return await all(futures)