Stock system-information screenshot — unavailable
==================================================

The main stock session captured the home screen, Play Store screens, the
signed-out diagnostic attempt, and the remote-control fixture, but it did not
open Android Settings > About emulated device.

Two later stock boots were made specifically to capture that screen:

- `44883707183` with `PlayStore.enabled=yes`
- `44884847559` with `PlayStore.enabled=no`

Both completed Android boot (about 27-28 seconds) but stayed
`adb: device unauthorized` despite `-skip-adb-auth`, so no ADB command and no
UI session could run. Their emulator logs are retained in the failed runs.
Android properties for the successful stock run are in `configuration.txt`;
the Play Store About screen with the Play Store version and “Device is not
certified” is in `play-store-about.png`.

No system-information image was fabricated or copied from a different device.
