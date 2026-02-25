import std/[strutils, algorithm, asyncdispatch, times, random]

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = cast[byte](ord(c))

proc toBytesArray*(s: string, size: static int): array[size, byte] =
  result.fill(0'u8)
  for i in 0 ..< min(s.len, size):
    result[i] = byte(ord(s[i]))

proc hexStringToBytes*(s: string, size: static int): array[size, byte] =
  result.fill(0'u8)
  var cleanHex = s.toUpperAscii()
  if cleanHex.startsWith("0x"): 
    cleanHex = cleanHex[2..^1]
    
  for i in countup(0, min(cleanHex.len - 1, (size * 2) - 1), 2):
    if i + 1 < cleanHex.len:
      let byteIndex = i div 2
      if byteIndex < size:
        let hexByte = cleanHex[i..i+1]
        try:
          result[byteIndex] = fromHex[uint8](hexByte)
        except:
          echo "Failed to convert hex pair: ", hexByte
          result[byteIndex] = 0'u8

func fromBytes*(b: seq[byte]): string =
  return cast[string](b)

proc bToInt*(bytes: array[4, byte]): int =
  var bytesLen = bytes.len
  for i in 0..<bytesLen:
    result = result or (int(bytes[i]) shl ((bytesLen-1-i)*8))

  return result

proc genPeerId*(): string =
  const prefix = "-TT0001-"
  const alphabet = "abcdefghijklmnopqrstuvwxyz"
  randomize()
  var rndid = ""
  for _ in 0..<12:
    rndid.add(alphabet[rand(alphabet.len - 1)])
  return prefix & rndid
  
proc awaitWithTimeout*[T](futures: seq[Future[T]], timeoutMs: int = 30_000): Future[seq[T]] {.async.} =
  ## Generic async function that waits for futures with a timeout.
  ## Returns all successfully completed results within the timeout period.
  ##
  ## Parameters:
  ##   - futures: Sequence of futures to wait for
  ##   - timeoutMs: Timeout in milliseconds (default: 30 seconds)
  var remainingFutures = futures
  var results: seq[T] = @[]
  
  let startTime = epochTime()
  
  while remainingFutures.len > 0:
    let elapsed = int((epochTime() - startTime) * 1000)
    if elapsed >= timeoutMs:
      echo "Timeout reached (", timeoutMs div 1000, "s), collected ", results.len, " results"
      break
    
    # Check which futures have completed
    var completedIndices: seq[int] = @[]
    for i in 0..<remainingFutures.len:
      if remainingFutures[i].finished:
        completedIndices.add(i)
    
    # Collect results from completed futures
    for i in countdown(completedIndices.high, 0):
      let idx = completedIndices[i]
      try:
        let result = await remainingFutures[idx]
        results.add(result)
      except:
        discard  # Ignore failed futures
      remainingFutures.delete(idx)
    
    # Small sleep to avoid busy waiting
    if remainingFutures.len > 0:
      await sleepAsync(100)
  
  return results
