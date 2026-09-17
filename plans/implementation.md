# Implementation and validation

Implemented September 17, 2026. Run `./bin/build`, then `./build/monologue`. Arch packaging is available through `./bin/install`.

The native application implements remembered camera/microphone selection, automatic maximum video resolution, live preview and microphone metering, Space recording/pause/resume, Finish, playback, portal Save, direct Omacut handoff, and retained recording recovery/discard.

Theme syncing follows Omacut's current-theme path and updates live after either a colors-file edit or a theme-symlink switch. The foreground on accent buttons is selected for contrast. Theme tests use temporary fixtures and do not change desktop configuration.

## Capture decisions established during implementation

- Use Qt's FFmpeg backend and custom video/audio inputs. One monotonic timeline removes pauses before encoding, while preview and metering continue. Native recorder pause is not used.
- Let the first frames initialize the encoders. Providing input format hints exposed a startup readiness issue with Qt 6.11.
- Give recording frames independent timestamp metadata using a public `QAbstractVideoBuffer` wrapper. Plain `QVideoFrame` copies share timestamps as well as their image data.
- Qt's audio encoder counts samples. Materialize timing gaps as silence and trim overlaps so audio remains aligned across pauses. The meter reads the same PCM stream.
- Capture microphone PCM through libpulse with measured server/device latency. Anchoring a sample counter to the first Qt callback can permanently shift audio by the initial buffering delay. Recompute capture timestamps from the audio server's timing information.
- Keep recorded interval history so delayed buffers captured before Pause remain part of the take. At Finish, wait for both capture streams to pass the cutoff before padding tails and closing the encoder, with a two-second interruption timeout.
- Quantize video timestamps to the selected recording rate and preserve the maximum source dimensions. Actual camera delivery can be below its advertised frame rate; the interface says “up to” the selected ceiling.
- Remux the finished MP4 without re-encoding to normalize packet durations and add fast-start metadata. Explicitly preserve PTS and DTS during that operation.

## Checks completed

- Release build with Qt 6.11.2 and FFmpeg 9.0.1.
- `./bin/test`: backend and QML suites pass. Coverage includes format ranking, pause timing, PCM levels, atomic copying, live theme switching, independent frame metadata, actual H.264/AAC encoding and decoding, missing initial audio, save cancellation, overwrite acceptance/decline, save failure, retained takes, discard, keyboard shortcuts, key repeat, and minimum-size layout.
- A decoded flash/click regression simulates 100 ms microphone delivery latency and delayed camera frames across Pause, Resume, and Finish. All four events remain aligned within 10 ms, including the last events before Pause and Finish.
- QML lint passes with unqualified context-property warnings disabled; the runtime QML test reports no warnings.
- Desktop entry validation and shell syntax checks pass.
- Short real-device capture at 1920 × 1080, with a pause/resume and restored settings. The final clip contains H.264 video and 48 kHz stereo AAC; `ffmpeg` decodes it without errors. Its audio/video stream durations differ by about 51 ms.
- After the audio timing fix, the remembered Cam Link 4K and Shure MV7+ completed a short 3840 × 2160 capture with pause/resume. H.264 video and 48 kHz mono AAC decode without errors; the final buffers arrived before the timeout. This validates the hardware capture path, not physical lip sync.
- The installed Omacut opens the finalized file. The original remains available after the editor is closed.
- Native offscreen startup passes. Simulated-source UI screenshots at 960 × 700 and 640 × 460 were visually inspected.

Real-device checks use separate settings and retain test clips under `/tmp/monologue-camera-check/`; they do not change the main application's source preferences. The optional `./bin/test-camera` helper records a short test explicitly and is excluded from the automated suite.

## Remaining manual checks

Long-take lip sync/drift, sustained 4K throughput, physical device removal during recording, and every desktop portal/backend combination still need device-specific checks. The short hardware test establishes capture and file validity; duration agreement alone does not establish lip sync. See the acceptance list in [the original plan](monologue.md).
