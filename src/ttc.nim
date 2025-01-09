import ttc/[magnet, peers, pwp]
import nanoid
import std/asyncdispatch


let x = parse_magnet(mag_str)
let id = "ttc_" & generate(size=16)

var tresp =  waitFor connect_trackers(id, x)

for p in tresp:
    discard contact(id, x.InfoHash, p.Peers)