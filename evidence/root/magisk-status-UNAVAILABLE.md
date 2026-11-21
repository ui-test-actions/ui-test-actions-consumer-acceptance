Magisk status screen — unavailable
==================================

The Magisk app package was installed from the official v31.1 APK:

- `pm list packages` contained `com.topjohnwu.magisk`
- `aapt dump badging` of the installed APK declared
  `launchable-activity: name='com.topjohnwu.magisk.ui.MainActivity'`
- Settings > Apps showed the package, but the app-info screen offered only
  Archive / Uninstall / Force stop, not Open
- `cmd package resolve-activity ...` returned "No activity found"
- `am start -W -n com.topjohnwu.magisk/.ui.MainActivity` returned
  "Error type 3: Activity class does not exist"
- After the next cold boot the package directory was gone entirely; logcat
  showed `PackageManager: Package com.topjohnwu.magisk unavailable` and
  `incfs ... No such file or directory`

The visible evidence is in `magisk-app-info.png` and the root logcat. The
Magisk status screen itself was therefore not capturable. This is a platform
packaging limitation in this rootAVD/Magisk 31.1/API 35 configuration, not a
failure of the `su` path: `su -c id` returned `uid=0(root)` both before and
after the second cold boot.

The experiment therefore reports:
- Magisk root access: PASS (CLI evidence)
- Magisk app status screen: BLOCKED (no launchable activity)
- Magisk module loading: FAIL (module installed, removed on boot)
