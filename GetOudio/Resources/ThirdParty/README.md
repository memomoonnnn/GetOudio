# ThirdParty Components

This source directory stores tools that are private to Get Oudio. Xcode copies only the required child folders into the app bundle Resources root. Do not install `ncmdump` or `apple-music-downloader` into a global path for normal app operation.

Expected release layout:

- `ncmdump/bin/ncmdump`
- `apple-music-downloader/apple-music-downloader`
- `apple-music-downloader/config.yaml.template`

The Apple Music wrapper is managed as a Docker image, not as an embedded macOS executable. The sandboxed App calls its Background Agent over Mach XPC; that Agent calls the non-sandbox Runtime Worker over a separate Mach service. Only the Worker accesses Docker, Colima, Lima, GPAC, the downloader binary, and the external managed runtime under `~/Library/Application Support/GetOudioV2`. Requests and credentials are never persisted as transport files, and legacy App Group data is not read, migrated, or removed.

The current development build embeds project-private `ncmdump` and `apple-music-downloader` binaries. The `apple-music-downloader` executable is built from the Get Oudio fork at `https://github.com/memomoonnnn/apple-music-downloader`; by default `script/build_apple_music_downloader.sh` expects a sibling checkout at `../apple-music-downloader-get-oudio`, builds a stripped `darwin/arm64` binary with `go build -trimpath -ldflags="-s -w"`, and copies it back into this directory. License notices, signature review, and final packaging metadata should be completed before distribution.
