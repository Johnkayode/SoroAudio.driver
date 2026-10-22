# Soro Audio Driver

Soro Audio Driver is the macOS virtual-microphone piece of **Soro**, a noise-cancellation microphone project. It gives macOS and audio apps an input device called **Soro Audio**. Soro’s audio-processing app can send its cleaned microphone signal to that device, and then a call, recording, or streaming app can select it like any other microphone.

```text
Physical microphone → Soro noise-cancellation app → Soro Audio → call / recording app
```

The driver is built from [BlackHole](https://github.com/ExistentialAudio/BlackHole), an open-source CoreAudio virtual audio driver, with Soro-specific device identity and audio settings. **The driver provides the virtual audio endpoint; it does not capture a physical microphone or perform noise cancellation on its own.** The Soro processing app (or another audio source configured to provide audio to this device) is needed for a useful microphone signal.

## What it provides

- A CoreAudio input device named **Soro Audio**.
- A two-channel, 48 kHz default format, configurable for the Soro setup.
- A BlackHole-based macOS AudioServerPlugIn driver, built as a `.driver` bundle.
- Scripts to build, install, check, and uninstall the driver.

## Requirements

- macOS with Apple’s Xcode command-line tools (`xcode-select --install`).
- The BlackHole Git submodule, available by cloning with submodules or initializing it after cloning.
- Administrator access to install or remove a system-wide CoreAudio driver.
- Optional: `sox` for the audio round-trip portion of the test script (`brew install sox`).
- For a signed, notarized build: a Developer ID signing identity and Apple notarization credentials.

The project’s build script sets a macOS deployment target of 10.13. Actual compatibility also depends on the macOS and Xcode versions used to build and test it.

## Get the source

Clone the Soro Audio Driver repository with its BlackHole submodule:

```sh
git clone --recurse-submodules <repository-url>
cd <repository-directory>
```

If you already cloned without submodules, initialize them from the repository root:

```sh
git submodule update --init --recursive
```

## Configure

The build reads local configuration files that are intentionally ignored by Git. Create them from the checked-in examples:

```sh
cp config/driver.env.sample config/driver.env
cp config/credentials.env.sample config/credentials.env
```

Edit `config/driver.env` to set the driver name, CoreAudio bundle ID, device name and UID, channel count, sample rate, and stream direction. The sample config creates a two-channel, 48 kHz input-only device called **Soro Audio**, packaged as `SoroAudio.driver`.

Edit `config/credentials.env` only if you plan to sign and notarize a distributable build. Keep real credentials private: the local `config/*.env` files are ignored by Git and should never be committed or shared. The unsigned development build still expects both files to exist, but it does not use the signing credentials.

## Build

For a local development build without code signing or notarization:

```sh
./scripts/build.sh --skip-notarize
```

The output driver bundle is written to `dist/SoroAudio.driver` by default. Despite the option name, `--skip-notarize` skips **both signing and notarization**; use this for local testing, not distribution. The build script requires the configuration files above, Xcode command-line tools, and the BlackHole submodule.

For a signed and notarized build, fill in the signing and Apple notarization values in `config/credentials.env`, then run:

```sh
./scripts/build.sh
```

This signs the driver, submits it to Apple’s notarization service, and staples the accepted ticket to the bundle. Distribution signing and notarization require valid Apple Developer credentials.

## Install and use

Build the driver, then install it into the system-wide CoreAudio HAL plug-in folder:

```sh
sudo ./scripts/install.sh
```

The install script verifies the bundle signature when possible, copies the driver to `/Library/Audio/Plug-Ins/HAL`, and restarts `coreaudiod` so macOS can discover it. For a driver bundle at a different path, pass that path to the script:

```sh
sudo ./scripts/install.sh --driver-path "/path/to/SoroAudio.driver"
```

After installation:

1. Open **System Settings → Sound → Input**, or the audio input settings in your application.
2. Choose **Soro Audio** as the microphone.
3. Make sure the Soro noise-cancellation app is running and routing its processed audio to the virtual microphone.

Some applications cache their audio-device list. If Soro Audio does not appear immediately, quit and reopen the application or check **Audio MIDI Setup**. macOS may also ask the receiving app for microphone access.

## Verify the installation

Run the project’s diagnostic script:

```sh
./scripts/test.sh
```

It checks whether the driver is installed and visible to macOS, inspects its signature and plug-in registration, and looks for related `coreaudiod` errors. If `sox` is installed, it also attempts a short audio round-trip. That audio test requires the Soro processing/routing path to be running; the virtual driver alone does not generate microphone audio.

To inspect CoreAudio logs while debugging:

```sh
log stream --predicate 'process == "coreaudiod"' --level debug
```

## Uninstall

Remove the system-installed Soro driver and restart CoreAudio:

```sh
sudo ./scripts/uninstall.sh
```

This removes `SoroAudio.driver` from `/Library/Audio/Plug-Ins/HAL`. If you changed `DRIVER_BUNDLE_NAME` in the driver configuration, the uninstall script uses that configured bundle name.

## Configuration reference

The defaults in `config/driver.env.sample` are:

| Setting | Default | Purpose |
| --- | --- | --- |
| `DRIVER_NAME` | `Soro Audio` | Driver’s display name |
| `BUNDLE_ID` | `com.soro.audio.driver` | CoreAudio plug-in bundle identifier |
| `DEVICE_NAME` | `Soro Audio` | Name shown in macOS and audio apps |
| `DEVICE_UID` | `SoroAudio_UID` | Persistent CoreAudio device identifier |
| `CHANNELS` | `2` | Number of audio channels |
| `SAMPLE_RATE` | `48000` | Default sample rate in Hz |
| `kDevice_HasInput` | `true` | Exposes the device as an audio input |
| `kDevice_HasOutput` | `false` | Does not expose an audio output |
| `DRIVER_BUNDLE_NAME` | `SoroAudio.driver` | Built and installed bundle name |

Keep the channel count and sample rate consistent with the audio produced by the Soro app. The build script injects these settings when compiling the BlackHole source.

## Troubleshooting

- **The driver does not show up:** Check that `dist/SoroAudio.driver` exists, install it with `sudo`, then reopen Audio MIDI Setup or restart the audio app. The install script restarts `coreaudiod`; if needed, you can do so manually with `sudo killall coreaudiod`.
- **The device appears, but apps receive silence:** Confirm the Soro processing app is running, its output is routed to Soro Audio, and its channel count and sample rate match the driver configuration.
- **The test reports that the device is missing:** Check the install location at `/Library/Audio/Plug-Ins/HAL/SoroAudio.driver` and inspect the test’s `system_profiler` and `pluginkit` results.
- **An unsigned development build is blocked:** The build made with `--skip-notarize` is intended for local development and is not signed or notarized. Build and install a properly signed/notarized bundle for distribution.
- **The round-trip test is skipped:** Install `sox` with `brew install sox`. The round-trip also needs a working Soro audio-routing path.

## Repository layout

```text
assets/                  Soro driver icon
config/                  Example driver and signing configuration
external/blackhole.git/  BlackHole Git submodule
scripts/                 Build, install, test, and uninstall scripts
dist/                    Local build output (ignored by Git)
```

## Acknowledgements and licensing

This driver builds on [BlackHole by Existential Audio](https://github.com/ExistentialAudio/BlackHole), which is included as a Git submodule. BlackHole’s source license and attribution are in `external/blackhole.git/LICENSE`. Review the upstream license and any applicable terms before distributing a derivative build. This repository does not currently include a separate top-level license for the Soro-specific files.
