import std/[sequtils, sugar]
import pwp

proc update_state() = discard
proc build_availability_map() = discard
proc get_work() = discard
proc launch_worker() = discard

proc startDownload*(data: seq[PeerData]) = 
  if data.len == 0:
    echo "No peers found, cannot start download, something went wrong"
    return

  let meta = data.filter(p => p.Meta.File.PieceHashes.len > 0)[0].Meta
  let num_pieces = meta.File.PieceHashes.len
  let piece_len = meta.File.PieceLength

  build_availability_map()
