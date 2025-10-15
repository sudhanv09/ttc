import std/[asyncdispatch, sequtils, strformat, random, math, algorithm, tables]
import pwp, messages

const BLOCK_SIZE* = 16_384

type
  BlockStatus* = enum
    Pending  
    Requested
    Received 
    Verified 
    Failed   

  PieceStatus* = enum
    Missing
    InProgress
    Complete
    Failed

  # Represents a 16KB block within a piece
  Block* = object
    pieceIndex*: int
    offset*: int
    length*: int
    data*: seq[byte]
    status*: BlockStatus
    assignedPeer*: int  # Index of peer assigned to this block (-1 if none)

  # Represents a complete piece
  Piece* = object
    index*: int
    hash*: seq[byte]  # SHA1 hash from metadata
    length*: int
    blocks*: seq[Block]
    status*: PieceStatus
    retryCount*: int

  WorkItem* = object
    pieceIndex*: int
    offset*: int
    length*: int
    assignedPeer*: string
    attempts*: int 

  DownloadItem* = object
    name*: string
    pieces*: seq[Piece]
    workQueue*: seq[WorkItem]

  # Main coordinator
  DownloadManager* = ref object
    item*: Table[string, DownloadItem]

proc buildPieces(meta: MetaDataFiles): seq[Piece] =
  let totalLength = meta.Files.mapIt(it.Length).sum()
  let pieceLen = meta.PieceLength
  let numPieces = (totalLength + pieceLen - 1) div pieceLen

  result = newSeq[Piece](numPieces)
  for i in 0..<numPieces:
    let plen = if i == numPieces - 1:
      totalLength - (i * pieceLen)
    else:
      pieceLen

    var blocks: seq[Block] = @[]
    var offset = 0
    while offset < plen:
      let blen = min(BLOCK_SIZE, plen - offset)
      blocks.add Block(
        pieceIndex: i,
        offset: offset,
        length: blen,
        data: @[],
        status: Pending,
        assignedPeer: -1
      )
      offset += blen

    result[i] = Piece(
      index: i,
      hash: if i < meta.PieceHashes.len: meta.PieceHashes[i] else: @[],
      length: plen,
      blocks: blocks,
      status: Missing,
      retryCount: 0
    )

proc bitfieldHas*(bitfield: seq[byte], idx: int): bool =
  let byteIdx = idx div 8
  if byteIdx < 0 or byteIdx >= bitfield.len: return false
  let bit = 7 - (idx mod 8)
  ((bitfield[byteIdx] shr bit) and 1'u8) == 1'u8

proc computeRarity(peers: seq[PeerData], numPieces: int): seq[int] =
  var rarity = newSeq[int](numPieces)
  for p in peers:
    for i in 0..<numPieces:
      if bitfieldHas(p.Piece, i):
        rarity[i].inc
  return rarity

proc build_work_queue*(state: seq[Piece], peers: seq[PeerData]): seq[WorkItem] =
  var queue: seq[WorkItem]
  let rarity = computeRarity(peers, state.len)
  randomize()

  for p in state:
    if p.status == Complete:
      continue
    for b in p.blocks:
      if b.status in {Pending, Failed}:
        queue.add WorkItem(
          pieceIndex: p.index,
          offset: b.offset,
          length: b.length,
          assignedPeer: "",
          attempts: 0
        )

  # Sort rarest-first, breaking ties randomly
  queue.sort(proc(a, b: WorkItem): int =
    let ra = if a.pieceIndex < rarity.len: rarity[a.pieceIndex] else: high(int)
    let rb = if b.pieceIndex < rarity.len: rarity[b.pieceIndex] else: high(int)
    result = cmp(ra, rb)
    if result == 0: result = rand(2) * 2 - 1 
  )

  echo &"Built work queue with {queue.len} blocks (rarest-first)"
  return queue


proc get_work() = discard
proc launch_worker() {.async.} = discard

proc startDownload*(data: seq[PeerData]) =
  if data.len == 0:
    echo "No peers found, cannot start download"
    return

  let maybeMeta = data.filterIt(it.Meta.File.PieceHashes.len > 0)
  if maybeMeta.len == 0:
    echo "No valid metadata from peers"
    return
  let meta = maybeMeta[0].Meta

  var state = buildPieces(meta.File)
  let queue = build_work_queue(state, data)

  var item = DownloadItem(
    name: meta.File.Name,
    pieces: state,
    workQueue: queue
  )

  echo &"Ready to download {state.len} pieces from {data.len} peers."
  echo &"Total blocks queued: {item.workQueue.len}"
