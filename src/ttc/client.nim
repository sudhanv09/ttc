import peers, magnet, pwp, utils
import std/[asyncdispatch, times, strutils, sequtils]


proc start_client*(mag_str: string) {.async.} = 
  let val = parse_magnet(mag_str)
  let id = genPeerId()

  echo "connecting to trackers"

  let t0 = epochTime()
  var tresp =  waitFor connect_trackers(id, val)
  let elapsed = epochTime() - t0

  echo "Finished fetching peers: ", elapsed.formatFloat(format=ffDecimal, precision=3)

  echo "contacting peers"
  var peer_bucket = tresp.mapIt(it.Peers).concat()

  echo "got peer pool: ", peer_bucket.len
  discard waitFor contact(id, val.InfoHash, peer_bucket)

