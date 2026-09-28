# ThirdParty Components

This source directory stores tools that are private to Get Oudio. Xcode copies only the required child folders into the app bundle Resources root. Do not install `ncmdump` or `apple-music-downloader` into a global path for normal app operation.

Expected release layout:

- `ncmdump/bin/ncmdump`
- `apple-music-downloader/apple-music-downloader`
- `apple-music-downloader/libtemari.dylib`
- `apple-music-downloader/config.yaml.template`

The Apple Music wrapper-lite QEMU package is downloaded by the non-sandbox Runtime Worker into `~/Library/Application Support/GetOudioV2`, not embedded in the App. The App calls its Background Agent over Mach XPC; that Agent calls the Worker over a separate Mach service. The Worker keeps the writable account disk outside the versioned QEMU package and retains old Colima data during migration. Credentials and 2FA codes travel only in XPC memory and QEMU standard input, never in arguments or transport files. Raw guest serial output is not persisted.

The current development build embeds project-private `ncmdump`, `apple-music-downloader`, and `libtemari.dylib`. The downloader is built from the Get Oudio fork at `https://github.com/memomoonnnn/apple-music-downloader`; by default `script/build_apple_music_downloader.sh` expects a sibling checkout at `../apple-music-downloader-get-oudio`, builds a stripped `darwin/arm64` binary with `go build -trimpath -ldflags="-s -w"`, and copies it here with Temari. License notices, signature review, and final packaging metadata should be completed before distribution.
