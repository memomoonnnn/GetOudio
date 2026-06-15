# ThirdParty Components

This directory is copied into the app bundle and is reserved for tools that are private to Get Oudio. Do not install `ncmdump` or `apple-music-downloader` into a global path for normal app operation.

Expected release layout:

- `ThirdParty/ncmdump/bin/ncmdump`
- `ThirdParty/apple-music-downloader/apple-music-downloader`
- `ThirdParty/apple-music-downloader/config.yaml.template`

The Apple Music wrapper is managed as a Docker image, not as an embedded macOS executable. Get Oudio uses Docker CLI with the Colima context to run `ghcr.io/itouakirai/wrapper:x86` as `linux/amd64` and stores mutable wrapper data under the app-managed `AppleMusicWrapper/rootfs/data` directory.

The current development build embeds project-private `ncmdump` and `apple-music-downloader` binaries. License notices, signature review, and final packaging metadata should be completed before distribution.
