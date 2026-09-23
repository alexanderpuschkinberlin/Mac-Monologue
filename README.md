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

A native macOS recorder for talking heads and screen tutorials. Pick a camera and a
microphone once, press **Space**, talk, press **Space** to pause, **⌘↩** to finish —
the clip lands in `~/Movies/Monologue`.

Or switch to **Screen + Camera**: your screen, with you as a round bubble in a corner
you pick — the tutorial look you know from YouTube, without editing it together
afterwards. Pause and finish with a global shortcut while you present.

It is not a port. The Linux original spends much of its code on problems macOS
does not have — it bypasses Qt's audio layer to talk to libpulse directly just
to get trustworthy capture timestamps, and shells out to `ffmpeg` to finalize
each take. Here `AVCaptureSession` delivers camera and microphone buffers on one
synchronized clock, and `AVAssetWriter` writes a faststart-optimized file
itself, so **Mac-Monologue has no runtime dependencies at all**.

## What it does

**Camera**
- Camera and microphone at **1080p30**, encoded to **HEVC + AAC** in `.mp4`
- **Pause and resume mid-take** — the paused interval is removed, and one
  continuous file comes out
- **Mirror the recording** if you want to: the preview always looks like a mirror,
  the file only when you ask

**Screen + Camera**
- Any connected screen at a **2560-px long edge** — slide text stays sharp
- **You as a round bubble** in the corner you pick, in three sizes; the preview shows
  exactly what is recorded, bubble included
- **System audio mixed with your microphone** into one track, so a video in your
  slides can be heard
- The mouse pointer and your clicks are shown; Mac-Monologue never records its own window
- If the camera drops out — an iPhone that locks — the screen keeps recording

**Everywhere**
- **Global shortcuts** and an always-visible **menu bar item** with a red dot and the
  running time, so you can pause and finish without leaving your presentation
- Live **microphone meter** in dBFS with peak-hold and a clipping indicator
- Play the finished take back before you keep it
- Remembers your devices by unique ID; a missing one shows as *unavailable*
  rather than silently switching to another
- **Reveal in Finder**, and discard moves the file to the Trash
- Welcome steps on first launch, with a drawing of where your fingers go

## Shortcuts

**From any app** — also while presenting. Changeable in Settings.

| Key | |
|---|---|
| `⌃⌥⌘R` | Record → Pause → Resume |
| `⌃⌥⌘↩` | Finish the take |

**In the Mac-Monologue window**

| Key | |
|---|---|
| `Space` | Record → Pause → Resume, or play the finished clip |
| `⌘↩` | Finish the take |
| `⌫` | Discard (always confirms) |
| `⌘N` | New recording |
| `⇧⌘R` | Reveal in Finder |
| `⌘,` | Settings |
| `?` | Keyboard shortcuts |

## Requirements

Apple Silicon, macOS 15 or later. Building needs Xcode and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Building

```sh
bin/build           # build Debug
bin/run             # build and launch, replacing any running instance
bin/test            # unit tests — no camera, microphone or screen access needed
bin/test-camera     # real takes in both modes, the files inspected afterwards
bin/release         # signed Release build plus a zip in dist/
```

The scripts export `DEVELOPER_DIR` themselves, so `sudo xcode-select -s` is not
required.

**Run `bin/make-signing-cert` once** before working on screen recording. macOS ties
the camera, microphone and screen recording permissions to the app's code signature;
without a stable certificate every rebuild looks like a new app and has to be granted
them again.

## Installing

The app is not notarized. On first launch macOS will refuse to open it; go to
**System Settings → Privacy & Security** and choose **Open Anyway**. The welcome
steps then ask for the camera, the microphone and screen recording, and restart the
app once so screen recording takes effect. Nothing else to install.

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
and no crash recovery.

**Not in the original at all:** the Screen + Camera mode with the bubble and mixed
system audio, global shortcuts, the menu bar item, mirroring, and the welcome steps. [`DESIGN.md`](DESIGN.md) records every such decision and
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
