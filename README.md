# Mac-Monologue

A native macOS talking-head recorder. Pick a camera and a microphone once, press
**Space**, talk, press **Space** to pause, **⌘↩** to finish — the clip lands in
`~/Movies/Monologue`.

Modeled on [omacom/monologue](https://github.com/omacom/monologue), DHH's Qt 6
webcam recorder for Omarchy, and written from scratch in Swift for the Mac.

It is not a port. The Linux original spends much of its code on problems macOS
does not have — it bypasses Qt's audio layer to talk to libpulse directly just
to get trustworthy capture timestamps, and shells out to `ffmpeg` to finalize
each take. Here `AVCaptureSession` delivers camera and microphone buffers on one
synchronized clock, and `AVAssetWriter` writes a faststart-optimized file
itself, so **Mac-Monologue has no runtime dependencies at all**.

## What it does

- Camera and microphone capture at **1080p30**, encoded to **HEVC + AAC** in `.mp4`
- **Pause and resume mid-take** — the paused interval is removed, and one
  continuous file comes out
- Live **microphone meter** in dBFS with peak-hold and a clipping indicator
- Play the finished take back before you keep it
- Remembers your devices by unique ID; a missing one shows as *unavailable*
  rather than silently switching to another camera
- **Reveal in Finder**, and discard moves the file to the Trash

## Shortcuts

| Key | |
|---|---|
| `Space` | Record → Pause → Resume, or play the finished clip |
| `⌘↩` | Finish the take |
| `⌫` | Discard (always confirms) |
| `⌘N` | New recording |
| `⇧⌘R` | Reveal in Finder |
| `?` | Keyboard shortcuts |

## Requirements

Apple Silicon, macOS 14 or later. Building needs Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Building

```sh
bin/build           # build Debug
bin/run             # build and launch, replacing any running instance
bin/test            # unit tests — no camera or microphone needed
bin/test-camera     # opt-in smoke test against real hardware
bin/release         # signed Release build plus a zip in dist/
```

The scripts export `DEVELOPER_DIR` themselves, so `sudo xcode-select -s` is not
required.

## Installing

The app is not notarized. On first launch macOS will refuse to open it; go to
**System Settings → Privacy & Security** and choose **Open Anyway**. Then grant
camera and microphone access once. Nothing else to install.

## Design

[`DESIGN.md`](DESIGN.md) records the decisions and why they were made, including
the ones deliberately taken differently from the original.

## License

MIT
