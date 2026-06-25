# ThirdParty Components

This source directory stores tools that are private to Get Oudio. Xcode copies only the required child folders into the app bundle Resources root. Do not install `ncmdump` or `apple-music-downloader` into a global path for normal app operation.

Expected release layout:

- `ncmdump/bin/ncmdump`
- `apple-music-downloader/apple-music-downloader`
- `apple-music-downloader/config.yaml.template`

The Apple Music wrapper is managed as a Docker image, not as an embedded macOS executable. Get Oudio talks to `GetOudioAMRuntimeAgent`, which installs Docker CLI, Colima, Lima, and GPAC under the App Group `AppleMusicRuntime` directory, uses `ghcr.io/itouakirai/wrapper:arm` as `linux/arm64` on Apple Silicon and `ghcr.io/itouakirai/wrapper:x86` as `linux/amd64` on Intel, and stores mutable wrapper data under the same runtime root. GPAC defaults to the official macOS package and extracts its relocatable `GPAC.app/Contents/MacOS` runtime; `GET_OUDIO_GPAC_PACKAGE_URL` is an optional override passed from the main app to the agent.

The current development build embeds project-private `ncmdump` and `apple-music-downloader` binaries. License notices, signature review, and final packaging metadata should be completed before distribution.
