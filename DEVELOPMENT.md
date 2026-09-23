# Developing Mac-Monologue

Everything for building, testing and publishing the app. What it does and how to
install it is in the [README](README.md); why it is built the way it is, in
[DESIGN.md](DESIGN.md).

## Requirements

Apple Silicon, macOS 15 or later, Xcode, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The
scripts export `DEVELOPER_DIR` themselves, so `sudo xcode-select -s` is not needed.

## Building and running

```sh
bin/build           # Debug build
bin/run             # build and launch, replacing any running instance
bin/release         # signed Release build and a zip in dist/
```

## The signing certificate

Mac-Monologue is signed with a self-signed certificate, **Mac-Monologue
Self-Signed**, rather than an Apple Developer ID. Create it once:

```sh
bin/make-signing-cert
```

It matters more than it looks:

- macOS ties camera, microphone and screen recording permission to the app's
  signature. An ad hoc signed build looks like a new app every time and has to be
  granted everything again.
- **It is the only key to updates.** An installed copy accepts an update only if it
  is signed with this exact certificate. Lose it, and no installed copy can ever
  update again; everyone would have to reinstall and grant permissions anew.

So back it up, and keep the file and its password apart from this Mac — a password
manager is a good place:

```sh
bin/export-signing-cert                 # → ~/Desktop/Mac-Monologue-Signing.p12
```

To restore it on another Mac:

```sh
security import Mac-Monologue-Signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "" ~/Library/Keychains/login.keychain-db
```

The certificate is valid until 2036.

## Testing

```sh
bin/test            # unit tests — no camera, microphone, screen access or network
bin/test-camera     # a real take in camera mode, then screen mode
bin/test-update     # a real update, end to end, publishing nothing
```

`bin/test-camera` records across a real three-second pause and inspects the
file: its size, exactly one audio track as long as the video, and how the
screen's clock relates to the camera's. Flags vary a single take:

| Flag | |
|---|---|
| `--screen` | Screen + Camera |
| `--mirror` | mirror the recording |
| `--no-mic` | no microphone; in screen mode, system audio only |
| `--keep` | keep the file in `~/Movies/Monologue` to look at |
| `--hotkeys` | drive the take through the global shortcuts |

The screen phase is skipped, not failed, without screen recording permission, and
`--hotkeys` without the Accessibility permission synthetic key presses need.

`bin/test-update` builds the app as 0.3.0 into a throwaway Applications folder
and a 0.3.1 beside it, then checks that 0.3.0 finds, verifies, installs and
relaunches as 0.3.1 — and that it refuses a download with the wrong checksum
and one signed by anyone else, leaving itself untouched.

By hand, because it cannot be automated: whether mixed audio clicks at a pause;
the global shortcuts while presenting; the welcome steps on a fresh account.

## Releasing

1. Add a section for the new version at the top of `CHANGELOG.md`:

   ```markdown
   ## 0.4.0

   - What changed, written for the people using the app.
   ```

   That section becomes the release notes on GitHub and in the app's update window.

2. Commit, then:

   ```sh
   bin/publish 0.4.0
   ```

   It checks everything first — the certificate is present, the changelog has the
   section, the version is new — builds and signs, shows you what it is about to
   publish, and asks once. Then it stamps the date into the changelog, commits,
   tags `v0.4.0`, pushes, and creates the GitHub release with `Mac-Monologue.zip`.
   It never falls back to an ad hoc signature.

Installed copies find the new version within a day, or at once with *Check for
Updates…*.
