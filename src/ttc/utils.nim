import std/[strutils, algorithm]
import nanoid

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
  let rndid = generate(alphabet="abcdefghijklmnopqrstuvwxyz", size=12)

  return prefix & rndid