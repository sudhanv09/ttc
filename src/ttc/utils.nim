import std/[strformat, strutils, algorithm]
import nanoid

proc toByte(c: char): byte =
  byte(ord(c))

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = cast[byte](ord(c))

proc toBytesArray*(s: string, size: static int): array[size, byte] =
  result.fill(0'u8)
  for i in 0 ..< min(s.len, size):
    result[i] = s[i].toByte

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

proc fromBytes*(s: seq[byte]): string = 
  if s.len > 0:
    result = newString(s.len)
    copyMem(result.cstring, s.unsafeAddr, s.len)

proc bToString*(bytes: seq[byte]): string =
  result = "b'"
  for b in bytes:
    result.add(fmt"\x{b:02x}")  # Format each byte as hex
  result.add("'")

proc genPeerId*(): string = 
  const prefix = "-TT0001-"
  let rndid = generate(alphabet="abcdefghijklmnopqrstuvwxyz", size=12)

  return prefix & rndid