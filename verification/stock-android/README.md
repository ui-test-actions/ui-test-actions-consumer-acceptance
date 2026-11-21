# Stock Android emulator experiment

The independent consumer ran UI Test Actions v3.0.1 at `0c818c5d72e8c30c59bd1287c330a40392bf8e89`. The workflow was pinned to consumer commit `9d6df03a96718f527df2d0cac0dbba33e9e2b340`. An external Python client authenticated to a real Ubuntu 24.04 runner over Quick Tunnel. [Hosted run](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44873908904)

## Verified on the runner

- Android Emulator 37.3.10 booted Android 15 API 35 on x86_64 from image revision 9 of `system-images;android-35;google_apis_playstore;x86_64`. The build reported `user`, `release-keys`, and ADB shell UID 2000. [Runner and emulator configuration](stock-android-configuration.txt)
- An external semantic click changed the fixture label to **AFTER · Button tapped**. The device configuration changed from 320×640 to 640×320 and returned to 320×640. [Before the click](01-stock-fixture.png) · [After the click](02-native-button-applied.png) · [Landscape capture](03-landscape.png)
- The external client used `app.install` to install Parlor 1.0.0 and `app.launch` to start it. Its existing upstream bundle came from commit `0811b7a2dc359a7bba0bc08c942a0ed237e0031f` and was verified against SHA-256 `c8032952722e092ea9a3b44bcaacd8bba5e354795503513b5ca5f7071ca7194f` before disposable signing. An external semantic click opened Whodunit and the native UI showed **Pass and Play**. [Upstream package run](https://github.com/parlor-game/parlor/actions/runs/44848744079) · [Parlor home](04-parlor-installed-and-running.png) · [Whodunit setup](05-parlor-whodunit.png)

## Stock Play Integrity attempt

Google Play opened signed out and exposed Settings through the Options menu. The observer followed Google's documented stock diagnostic path, including tapping the Play Store version seven times and checking General. That screen exposed Notifications and no Developer options or Check integrity command. The official Update Play Store control said it would install a newer version, but that message alone established no installation. The final readback still showed version 41.3.25-31. [Final version recheck](13-version-recheck.png) [Google's stock diagnostic procedure](https://developer.android.com/google/play/integrity/additional-tools#check_the_device_integrity_verdict_from_any_device) · [Sign-in screen](06-stock-play-store.png) · [General settings](10-play-general.png) · [Update response](11-play-update-result.png) · [Recovered UI state](12-final-play-state.png)

| Verdict | Stock diagnostic | After AlwaysStrong |
| --- | --- | --- |
| MEETS_BASIC_INTEGRITY | Not measured | Not run |
| MEETS_DEVICE_INTEGRITY | Not measured | Not run |
| MEETS_STRONG_INTEGRITY | Not measured | Not run |
| MEETS_VIRTUAL_INTEGRITY | Not measured | Not run |

The stock Play Store produced no verdict. The rooting and module stages were outside this run because the requested sequence was intended to bypass Play Integrity attestation. The comparison has no measured change. This run contains no Magisk or module screenshots.

## Harness and transport observations

The first attempt booted the emulator and failed when the metadata collector invoked a second emulator process for its version and that invocation required `libpulse.so.0`. The retry read installed SDK package metadata directly and uploaded it independently of the live session. One read-only hierarchy response was lost during the Play Store check. A fresh authenticated client read the live screen and took another screenshot. The Action source used for the experiment required no patch. [First run](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44873707803) · [Structured external observations](observations.json)

The successful runner closed its six-minute lease. The external client recorded two successive HTTP 530 responses after the last live observation. [Lease trace](lease-observation.json) · [Runner log excerpt](runner-log-excerpt.txt) · [Download the GitHub configuration artifact](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44873908904/artifacts/14695415546)
