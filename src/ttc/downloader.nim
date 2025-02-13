import std/[asyncdispatch, asyncnet, os]
import pwp, messages

type
  PieceStatus = enum
    Missing,
    InProgress,
    Complete
  
  PieceInfo* = object
    Index*: int
    Status*: PieceStatus
    PieceLength*: int

  Completed* = seq[PieceInfo]


proc get_next_piece(bitfield: seq[byte], piece_list: Completed, total_pieces: int): int = 
  if bitfield.len * 8 < total_pieces:
    return -1

  for piece_info in piece_list:
    let i = piece_info.Index
    if i >= total_pieces:
      continue

    if piece_info.Status == Missing:
      let byte_idx = i div 8
      let bit_idx = 7 - (i mod 8)

      if byte_idx < bitfield.len and ((bitfield[byte_idx] shr bit_idx) and 1) == 1:
        return i
    
  return -1

proc receive_msg(s: AsyncSocket): Future[Message] {.async.} = 
  # get the length
  var msg_len_bytes = newSeq[byte](4)
  discard await s.recvInto(addr msg_len_bytes[0], 4)

  echo msg_len_bytes
  var msg_len = 0
  for i in 0..3:
    msg_len = (msg_len shl 8) or int(msg_len_bytes[i])

  if msg_len == 0:
    echo "Keeping alive"
    return Message(Id: pChoke)

  # message Id
  var msg_id = newSeq[byte](1)
  discard await s.recvInto(addr msg_id[0], 1)

  if PeerActions(msg_id[0]) == pPiece:
    var payload = newSeq[byte](msg_len - 1)
    discard await s.recvInto(addr payload[0], msg_len - 1)

    return Message(Id: PeerActions(msg_id[0]), Payload: payload)
  
  return Message(Id: PeerActions(msg_id[0]))

proc download_worker*(peer_data: PeerData) {.async.} = 
  if peer_data.Conn == nil:
    echo "invalid peer connection"
    return
  
  if peer_data.Piece.len == 0:
    echo "not bitfields found"
    return

  var completed_queue: Completed = @[]
  let total_pieces = if peer_data.Meta.File.PieceHashes.len > 0: 
    peer_data.Meta.File.PieceHashes.len 
  else: 
    return  # No pieces to download

  # Initialize all pieces as Missing
  for i in 0..<total_pieces:
    completed_queue.add(PieceInfo(
      Index: i,
      Status: Missing,
      PieceLength: if i == total_pieces-1: 
        peer_data.Meta.File.PieceLength mod METADATA_PIECE_SIZE 
      else: 
        peer_data.Meta.File.PieceLength
    ))

  var s = peer_data.Conn
  echo "sending interested"
  await s.sendInterested()

  # waiting for unchoke
  var count = 0
  while true:
    let msg = await s.receive_msg()
    if count > 10: break
    case msg.Id:
      of pUnchoke:
        echo "Peer unchoked us, can start requesting pieces"
        break
      of pChoke:
        echo "Peer choked us"
        echo "sleeping"
        sleep 1000
        count += 1
      else:
        echo "Got message type: ", msg.Id

  # download loop
  while true:
    let piece_idx = get_next_piece(peer_data.Piece, completed_queue, total_pieces)
    if piece_idx == -1:
      echo "No more pieces available from this peer"
      break

    completed_queue[piece_idx].Status = InProgress

    let piece_size = completed_queue[piece_idx].PieceLength
    const block_size = 16384  # 16KB blocks
    var offset = 0
    
    while offset < piece_size:
      let remaining = piece_size - offset
      let request_size = min(block_size, remaining)
      
      echo "Requesting piece ", piece_idx, " offset ", offset, " length ", request_size
      await s.sendRequest(piece_idx, offset, request_size)
      
      let msg = await receive_msg(s)
      case msg.Id:
        of pPiece:
          echo "Received piece data, length: ", msg.Payload.len
          # Here you should:
          # 1. Verify piece index and offset match what we requested
          # 2. Store the block data
          # 3. Verify the complete piece hash when all blocks are received
          
          offset += request_size
          if offset >= piece_size:
            completed_queue[piece_idx].Status = Complete
            echo "Piece ", piece_idx, " completed"
        of pChoke:
          echo "Peer choked us during download"
          completed_queue[piece_idx].Status = Missing
          await sleepAsync(1000)
          break
        else:
          echo "Unexpected message: ", msg.Id
          break

    # Add small delay between piece requests
    await sleepAsync(100)
