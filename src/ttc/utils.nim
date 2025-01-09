

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