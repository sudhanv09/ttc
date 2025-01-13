import std/[strformat, strutils]
import nanoid

proc toByte(c: char): byte =
  byte(ord(c))

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s:
    result[i] = cast[byte](ord(c))

proc toBytesArray*(s: string, size: static int): array[size, byte] =
  for i in 0 ..< size:
    result[i] = 0'u8  # Initialize with zeros
  for i in 0 ..< min(s.len, size):
    result[i] = s[i].toByte

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