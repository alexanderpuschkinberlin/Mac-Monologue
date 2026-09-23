# Changelog

Every version of Mac-Monologue, newest first. `bin/publish` takes the section of
the version it publishes as that release's notes, and the app shows them when it
offers an update.

## 0.3.1 — 2026-09-24

- The download page now explains the message macOS shows the first time you open
  Mac-Monologue, and how to get past it once.
- It also says which permissions the welcome steps ask for, and that they are kept
  when you install Mac-Monologue again.

## 0.3.0 — 2026-09-24

- Mac-Monologue now tells you when a new version is out, shows what changed, and
  installs it for you with one click — only if it is signed by the same developer.
- Download it from GitHub: one link that always gets the newest version.
- Fixed: after granting screen recording during setup, the restarted app could
  warn that its global shortcuts were taken by another app.

## 0.2.0 — 2026-09-23

- **Screen + Camera**: record a screen with yourself as a round bubble in a
  corner — four corners, three sizes, shown live before you start.
- System audio is recorded along with your microphone, in one track.
- Global shortcuts ⌃⌥⌘R and ⌃⌥⌘↩ pause and finish from any app, even while
  presenting, and a menu bar item shows a red dot and the running time.
- In screen mode the window gets out of the way while you record.
- Mirror the recording, if you want the saved file to look like a mirror.
- Welcome steps on first launch, with a drawing of where your fingers go.
- Settings for the shortcuts, the start-up mode and more.
- If the camera drops out mid-take, the screen keeps recording.

## 0.1.0 — 2026-09-20

- Record yourself with the camera and microphone you choose, at 1080p in HEVC.
- Pause and resume within one take — the pause is removed from the file.
- A live microphone meter with peak hold and a clipping warning.
- Play the take back, reveal it in Finder, or discard it to the Trash.
