import lib/[magnet_parser, trackers]
import std/[asyncdispatch, httpclient, strutils]

let magnet = "magnet:?xt=urn:btih:87D8113208929B518DCE9EADDCA3E4C74AC72F38&dn=Silo.S02E01.1080p.WEB.H264-SuccessfulCrab%5BTGx%5D&tr=udp%3A%2F%2Fopen.stealth.si%3A80%2Fannounce&tr=udp%3A%2F%2Ftracker.tiny-vps.com%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451%2Fannounce&tr=udp%3A%2F%2Fexplodie.org%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.cyberia.is%3A6969%2Fannounce&tr=udp%3A%2F%2Fipv4.tracker.harry.lu%3A80%2Fannounce&tr=udp%3A%2F%2Fp4p.arenabg.com%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.birkenwald.de%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.moeking.me%3A6969%2Fannounce&tr=udp%3A%2F%2Fopentor.org%3A2710%2Fannounce&tr=udp%3A%2F%2Ftracker.dler.org%3A6969%2Fannounce&tr=udp%3A%2F%2Fuploads.gamecoast.net%3A6969%2Fannounce&tr=https%3A%2F%2Ftracker.foreverpirates.co%3A443%2Fannounce&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce&tr=http%3A%2F%2Ftracker.openbittorrent.com%3A80%2Fannounce&tr=udp%3A%2F%2Fopentracker.i2p.rocks%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.internetwarriors.net%3A1337%2Fannounce&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969%2Fannounce&tr=udp%3A%2F%2Fcoppersurfer.tk%3A6969%2Fannounce&tr=udp%3A%2F%2Ftracker.zer0day.to%3A1337%2Fannounce"

proc getInfo(tracker: string, req: TrackerRequest): Future[string] {.async.} = 
    let client = newAsyncHttpClient()
    try:
        echo "trying: ", tracker
        let url = buildAnnounceUrl(tracker, req)
        let response = await client.get(url)
        if response.status == "200 OK":
            # echo "Response from ", tracker, ": ", body
            return await response.body
    except Exception as e:
        return ""


proc sendRequestsToTrackers(trackers: seq[string], req: TrackerRequest) {.async.} =
    var futures: seq[Future[string]] = @[]
    for tracker in trackers:
        futures.add(getInfo(tracker, req))
    
    let responses = await all(futures)

    for i, response in responses:
        if response != "":
            if response.startsWith("<"):
                continue
            discard parseResponse(response)



let parsed = parser(magnet)
let req = newTrackerRequest(parsed.infoHash)

waitFor sendRequestsToTrackers(parsed.trackers, req)