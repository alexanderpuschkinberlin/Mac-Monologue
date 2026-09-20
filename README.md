# Mac-Monologue

> A fork of **[omacom/monologue](https://github.com/omacom/monologue)** — David
> Heinemeier Hansson's webcam recorder for Omarchy, MIT licensed — rebuilt for
> Apple Silicon Macs.
>
> Not a line of the original C++ survives. It is Qt 6 on libpulse, with a
> `xdg-desktop-portal` picker and an `ffmpeg` finalize step, and none of that
> layer has an equivalent here. What carries over is the design. The
> implementation is Swift on AVFoundation — written because my Mac currently
> gives me the best video and audio quality I have available.

A native macOS talking-head recorder. Pick a camera and a microphone once, press
**Space**, talk, press **Space** to pause, **⌘↩** to finish — the clip lands in
`~/Movies/Monologue`.

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

## Relationship to the original

This is a fork in provenance, not in code. `master` still holds
[omacom/monologue](https://github.com/omacom/monologue) untouched; `main` removes
that implementation and rebuilds the same idea natively.

**Taken from the original:** the concept and the two-state flow (ready → preview),
pause and resume as the feature the whole design turns on, the keyboard shortcuts,
the device-memory behaviour where a missing camera shows as *unavailable* rather
than silently switching, the filename convention
`Monologue-yyyy-MM-dd-HHmmss.mp4`, and the clipping red `#f06c6c` in the
microphone meter.

**Deliberately different:** 1080p30 instead of the camera's maximum advertised
resolution — picking the maximum is what produces the original's "encoding cannot
keep up" failure; HEVC instead of H.264; `~/Movies/Monologue` instead of a staging
library with per-take manifests; Reveal in Finder instead of the Omacut handoff;
and no crash recovery. [`DESIGN.md`](DESIGN.md) records every such decision and
why it was made.

**Written from scratch:** all of `Sources/`, on AVFoundation. `AVCaptureSession`
delivers camera and microphone buffers on one synchronized clock, which is the
problem the original solves by bypassing Qt for libpulse, and `AVAssetWriter`
writes a faststart-optimized file itself, which is what the original calls
`ffmpeg` for.

## License

MIT — see [`LICENSE`](LICENSE), which carries both copyright lines: David
Heinemeier Hansson for the original Monologue, and Alexander Puschkin for this
macOS rewrite.
