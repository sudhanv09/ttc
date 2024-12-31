import std/[strutils, uri]

type
  MagnetData* = object
    infoHash*: string        
    displayName*: string     
    trackers*: seq[string]   
    exactLength*: int64      
    keywords*: seq[string]   
    sources*: seq[string]    
    peerAddresses*: seq[string] 

proc parser*(magnet: string): MagnetData = 
    var data = MagnetData(
    trackers: @[],
    keywords: @[],
    sources: @[],
    peerAddresses: @[]
    )

    if not magnet.startsWith("magnet:?"):
        return

    let params = magnet[8..^1].split("&")
    for p in params:
        let parts = p.split("=", maxsplit=1)
        if parts.len != 2: continue

        let 
            key = parts[0]
            value = decodeUrl(parts[1])

        case key:
          of "xt":
            if value.startsWith("urn:btih:"):
                data.infoHash = value[9..^1]
          of "dn":
            data.displayName = value
          of "tr":
            data.trackers.add(value)
          of "kt":
            data.keywords.add(value)
          of "xs":
            data.sources.add(value)
          of "x.pe":
            data.peerAddresses.add(value)
    
    return data

