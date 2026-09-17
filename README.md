# Monologue

A simple webcam recorder for Omarchy. Choose your camera and microphone once, then press **Space** to record. Press again to pause or resume the same take. **Finish** gives you a clip to save or open directly in Omacut.

- Remembers camera and microphone by device ID; missing inputs never silently switch.
- Automatically selects the camera's maximum advertised video resolution, preferring 30 fps at that resolution. Preview preserves the whole frame.
- Live microphone meter with peak hold and clipping indication, including while paused. No microphone playback through your speakers.
- Explicit No audio option for silent recordings.
- Live Omarchy accent syncing, including theme symlink switches. Dark chrome and a yellow fallback follow Omacut; button foregrounds adapt for contrast.
- H.264 MP4 with AAC audio, retained originals, atomic Save, and direct Omacut handoff.

## Build and run

Install a C++17 compiler, `make`, `qt6-base`, `qt6-declarative`, `qt6-multimedia` (Qt 6.8 or newer), and `ffmpeg`. Then:

```sh
./bin/build
./build/monologue
```

The save dialog requires `xdg-desktop-portal` and your desktop's portal backend. Install `omacut` to use **Open in Omacut**. Monologue uses Qt's FFmpeg multimedia backend for timestamped capture; the binary selects it automatically.

To build and install the Arch package:

```sh
./bin/install
```

## Shortcuts

| Key | Action |
| --- | --- |
| Space | Record / pause / resume; play / pause a finished clip |
| Ctrl+Enter | Finish the take |
| Ctrl+S | Save a finished clip |
| Q | Quit (offers to finish an active take) |
| ? | Keyboard help |

Tab focuses controls; Space activates a focused control normally. Capture shortcuts stop while dialogs and source dropdowns are open. Selectors stay locked through a take, including pauses.

## Recordings and settings

Recordings stay in the application's XDG data directory, normally `~/.local/share/omacom/monologue/recordings/`. The **Recordings** menu lists completed and interrupted takes, their sizes, and actions to reopen, inspect files, or discard them. Recovery never interrupts startup. Save copies the original without re-encoding. Closing Monologue or opening Omacut does not delete it; only explicit Discard deletes the original.

Device IDs and the last save directory live in the application's Qt settings, normally `~/.config/omacom/monologue.conf`. The theme is read from `~/.local/state/omarchy/current/theme/colors.toml`, as in Omacut. No Omarchy config is changed.

A disconnected source or encoder error stops the take and preserves its files. An unfinalized MP4 after a crash or power loss may not be playable. Maximum resolution is never silently reduced: if the device or encoder cannot sustain it, Monologue reports the problem.

## Development and validation

```sh
./bin/test
```

Tests cover format ranking, pause timing, PCM levels, atomic saving, theme file changes and symlink swaps, actual H.264/AAC encoding and decoding, and native QML keyboard/layout behavior with simulated sources. They run offscreen and do not activate a camera or microphone. The capture-independent backend uses an injected file picker for save and recovery tests. The QML tests write inspection screenshots to `/tmp/monologue-ui-*.png`.

The recording engine forwards native camera frames and one shared microphone PCM stream to timestamped Qt inputs. It removes paused intervals before encoding and uses the same microphone samples for the meter. Qt's audio encoder counts samples, so the writer pads genuine capture gaps and trims overlaps to maintain the common timeline. Preview and metering remain live while paused. Finish remuxes the MP4 without re-encoding to normalize packet durations and put playback metadata at the front of the file.

Run `./bin/test-camera` explicitly for a short real camera/microphone recording with a pause and resume. It uses separate `monologue-camera-check` settings and storage, and retains its output for inspection. It is never run by `bin/test`.

A real-camera check is still needed for each device/backend combination, particularly maximum-resolution throughput and synchronization over long takes. A short 1920 × 1080 hardware check passed on this machine; it does not establish long-take synchronization or 4K throughput. See [the plan](plans/monologue.md) for the manual acceptance checks.

## License

MIT. The portal file picker and theme-watching approach derive from [Omacut](../omacut), copyright David Heinemeier Hansson; attribution is retained in [LICENSE](LICENSE).
