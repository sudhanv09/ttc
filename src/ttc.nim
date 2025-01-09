import ttc/[magnet, peers, pwp]
import nanoid
import std/asyncdispatch


let x = parse_magnet(mag_str)
let id = "ttc_" & generate(size=16)

echo "connecting to trackers"
var tresp =  waitFor connect_trackers(id, x)

echo "contacting peers"
for peer in tresp:
    discard waitFor contact(id, x.InfoHash, peer.Peers)