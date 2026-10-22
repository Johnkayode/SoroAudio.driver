# Soro Audio Driver

Soro Audio is an input-only virtual audio driver for macOS. It exposes a input device named **Soro Audio** through which apps can send audio to other apps. The driver is built on [BlackHole](https://github.com/ExistentialAudio/BlackHole)

## Requirements

- macOS and Xcode command-line tools (`xcode-select --install`)
- Administrator access to install or remove the driver
- Optional: `sox` for the audio round-trip test (`brew install sox`)
- For distribution builds: an Apple Developer signing identity and notarization credentials

The build script sets a macOS deployment target of 10.13.

## Build

Clone the repository and its BlackHole submodule:

```sh
git clone --recurse-submodules https://github.com/Johnkayode/SoroAudio.driver.git
cd SoroAudio.driver
```

Create local configuration files from the examples:

```sh
cp config/driver.env.sample config/driver.env
cp config/credentials.env.sample config/credentials.env
```

The sample driver config builds a two-channel, 48 kHz input device named **Soro Audio**. Adjust `config/driver.env` if needed. The `.env` files are ignored by Git; keep real signing and notarization credentials private. Both files must exist to build, including for local development.

Build an unsigned local version:

```sh
./scripts/build.sh --skip-notarize
```

This skips both signing and notarization. The output is `dist/SoroAudio.driver`. For a signed and notarized build, fill in the credentials in `config/credentials.env` and run `./scripts/build.sh`.

## Install and use

```sh
sudo ./scripts/install.sh
```

The script installs the driver under `/Library/Audio/Plug-Ins/HAL` and restarts CoreAudio. Then select **Soro Audio** as the input device in macOS Sound settings or in your audio app. The Soro processing app must be running and providing audio to the virtual device.

## Test and uninstall

Check installation and device visibility with:

```sh
./scripts/test.sh
```

The optional round-trip test requires `sox` and a working Soro audio-routing path. To remove the driver:

```sh
sudo ./scripts/uninstall.sh
```

## Configuration

`config/driver.env.sample` contains the device name, bundle ID, UID, channel count, sample rate, input/output settings, and bundle name. Keep the sample rate and channel count aligned with the audio sent by Soro.

## Credits

This project uses [BlackHole](https://github.com/ExistentialAudio/BlackHole) as a Git submodule at `external/blackhole.git`. See `external/blackhole.git/LICENSE` for its license and attribution. Review upstream terms before distributing a derivative build. This repository has no separate top-level license for its Soro-specific files.
