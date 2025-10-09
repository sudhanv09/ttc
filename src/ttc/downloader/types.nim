import std/[tables]

type
  BlockStatus* = enum
    Pending      # Block not yet requested
    Requested    # Block requested from peer
    Received     # Block data received
    Verified     # Block verified as part of complete piece
    Failed       # Block request failed, needs retry

  PieceStatus* = enum
    Missing      # Piece not started
    InProgress   # Piece being downloaded
    Complete     # Piece downloaded and verified
    Failed       # Piece verification failed

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

  # Central state manager for download progress
  DownloadState* = object
    pieces*: seq[Piece]
    globalBitfield*: seq[byte]  # Tracks which pieces we have
    downloadedBytes*: int
    totalBytes*: int
    peerAvailability*: Table[string, seq[int]]  # PeerID -> pieces they have
    isComplete*: bool

  DownloadItem* = object
    name*: string
    state*: DownloadState

  # Main coordinator
  DownloadManager* = object
    item*: seq[DownloadItem]
