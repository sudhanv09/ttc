import ttc/[magnet, peers, pwp, utils]
import std/[asyncdispatch, times, strutils]


let x = parse_magnet(mag_str)
let id = genPeerId()

echo "connecting to trackers"

let t0 = epochTime()
var tresp =  waitFor connect_trackers(id, x)
let elapsed = epochTime() - t0

echo "Finished: ", elapsed.formatFloat(format=ffDecimal, precision=3)

echo "contacting peers"
var peer_bucket: seq[TPeers] = @[]
for peer in tresp:
    peer_bucket.add(peer.Peers)

echo "got peer pool: ", peer_bucket.len
discard waitFor contact(id, x.InfoHash, peer_bucket)