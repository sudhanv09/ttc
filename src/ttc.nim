import ttc/[magnet, peers]
import nanoid
import std/asyncdispatch


let x = parse_magnet(mag_str)
let id = generate(size=16)

discard waitFor connect_trackers("ttc_"&id, x)