# Package

version       = "0.1.0"
author        = "sudhanv09"
description   = "A tiny bittorrent client implementation"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["ttc"]


# Dependencies

requires "nim >= 2.0"

requires "bencode >= 0.1.0"
requires "nanoid >= 0.2.0"