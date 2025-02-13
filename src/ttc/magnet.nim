import std/[strutils, uri]

type Magnet* = object
  InfoHash*: string
  Name*: string
  Trackers*: seq[string]

proc parse_magnet*(link: string): Magnet = 
  if not link.startsWith("magnet:?"):
    raise newException(ValueError, "Invalid magnet link")

  let trimmed = link[8..^1]
  let dict = trimmed.split("&")

  var mag: Magnet
  for i in dict:
    let val = i.split("=")
    if val.len != 2: continue
    case val[0]:
      of "xt":
        mag.InfoHash = val[1][9..^1]
      of "dn":
        mag.Name = val[1]
      of "tr":
        mag.Trackers.add(val[1].decodeUrl)
  
  return mag
    