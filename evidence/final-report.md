# Android Emulator, rootAVD, Magisk, and Play Integrity — experimental report

**Date:** 2026-11-21  
**Repository under test:** [ui-test-actions/ui-test-actions-consumer-acceptance](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance)  
**Isolated branch:** `experiment/integrity-root-magisk` (not merged into `main`)  
**Primary action pin:** `ui-test-actions/ui-test-actions@0c818c5d72e8c30c59bd1287c330a40392bf8e89` (v3.0.1 action pin)

---

## 1. Executive summary

The GitHub-hosted Ubuntu runner had working KVM acceleration, and a clean
Android 15 / API 35 Google Play emulator booted. An external agent connected to
it through a real UI Test Actions session, captured screenshots, read the UI
tree, clicked semantically, installed and launched an APK, inserted Unicode
text, scrolled, used Back/Home, and verified session stability.

The genuine Play Store integrity diagnostic was **not available**:
`CHECK_UNAVAILABLE`. The Play Store was signed out; the documented seven-tap
unlock did not expose Developer options, so the Check integrity menu never
appeared. This is not an integrity failure and no verdict labels were invented.

On a separate disposable AOSP image, the pinned rootAVD commit patched the
Android 15 ramdisk, Magisk 31.1 booted, the ordinary ADB shell stayed UID 2000,
and an explicit Magisk `su -c id` returned `uid=0(root)` both before and after a
second cold boot. The guest had no outbound IP connectivity during the patch.

Magisk 31.1's app package was installed but had no resolvable launcher activity
and disappeared after a cold boot. Its module installer reported an incomplete
Magisk install until the runtime files were staged from the official APK; after
that the inert module installed successfully, but it was removed at the next
boot and its marker never ran. Module loading is therefore **FAIL** in this
configuration, even though root itself persisted.

AlwaysStrong v1.0.6.1 was reviewed statically. No explicit emulator support
claim exists in the reviewed tree. Its x86_64 TEE libraries are present, but the
default release has **no x86_64 Zygisk payload**, so the Play Integrity spoof
half is not theoretically complete on this ABI. Runtime compatibility and any
genuine verdict effect remain `UNVERIFIED`; the module was not executed against
the live verifier.

---

## 2. Environment

| Item | Value |
|---|---|
| Runner | GitHub-hosted `ubuntu-24.04`, image `20261116.133.1` |
| OS | Ubuntu 24.04.5 LTS, kernel `7.0.0-1014-aws` |
| Architecture | x86_64 |
| CPU / RAM / disk | 4 vCPU, 15 GiB RAM, 89 GiB free |
| KVM | `/dev/kvm` present; `emulator -accel-check`: “KVM (version 12) is installed and usable.” |
| Android Emulator | 37.3.10 |
| ADB | platform-tools 37.0.1 in preflight; job installed 37.0.3 |
| System image | `system-images;android-35;google_apis_playstore;x86_64`, revision 9 |
| AOSP image for root | `system-images;android-35;google_apis;x86_64`, revision 9 |
| Android | 15 / API 35 / x86_64 |
| Stock fingerprint | `google/sdk_gphone64_x86_64/emu64xa:15/AE3A.240806.036/12592187:user/release-keys` |
| Stock build type | `user`, `release-keys` |
| Stock security patch | 2024-09-05 |
| Play Store | 41.3.25-31 initially; 54.3.07-34 after self-update |
| Play Services | 24.23.35 initially; 26.45.31 finally |
| rootAVD | GitLab commit `613caa44371f85e1a461bc030e07ddc2d71afe32` |
| Magisk | v31.1, SHA-256 `89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7` |
| AlwaysStrong | v1.0.6.1, commit `35b80223db44332f8262cb78453d561a36c97ea1` |
| UI Test Actions | v3.0.1 action pin `0c818c5d72e8c30c59bd1287c330a40392bf8e89` |

The emulator package was not preinstalled on the hosted image. Installing it
revealed the previously encountered `libpulse.so.0` failure:

```
emulator: error while loading shared libraries: libpulse.so.0: cannot open shared object file
```

`libpulse0` was installed from Ubuntu, after which `emulator -version` and
`-accel-check` succeeded. This is recorded in
[`runner/acceleration.txt`](runner/acceleration.txt).

---

## 3. Experimental results

| Test | Result | Evidence |
|---|---|---|
| Runner acceleration | **PASS** | `runner/acceleration.txt` |
| Stock emulator boot | **PASS** | `stock/configuration.txt`, `stock/emulator.log` |
| Stock ADB authorization repeatability | **FAIL** in 2 of 3 later Play Store boots (boot completed, ADB stayed unauthorized) | `stock-supplement` and `stock-system` logs below |
| UI Test Actions connectivity | **PASS** | `ui-test-actions/interaction-results.json` |
| Remote UI control (screenshot, tree, semantic click, text, scroll, Back/Home, app launch/install) | **PASS** | stock screenshots 01-23 |
| Google Play Services availability | **PASS** | `stock/play-versions.txt`, `stock/gms-dumpsys.txt` |
| Genuine BASIC verdict | **CHECK_UNAVAILABLE** | `stock/integrity-result.json` |
| Genuine DEVICE verdict | **CHECK_UNAVAILABLE** | `stock/integrity-result.json` |
| Genuine STRONG verdict | **CHECK_UNAVAILABLE** | `stock/integrity-result.json` |
| Genuine VIRTUAL verdict | **CHECK_UNAVAILABLE** | `stock/integrity-result.json` |
| rootAVD patch | **PASS** | `root/patch.log`, `root/ramdisk-hashes.txt` |
| Magisk root access | **PASS** | `root/root-verification.txt`, `root/grant.txt` |
| Root persistence after cold boot | **PASS** | `root/reboot-verification.txt` |
| Inert module installation | **PASS** | `root/module-install.txt` |
| Inert module loading after boot | **FAIL** (module directory and marker absent) | `root/module-installed.txt`, `root/reboot-verification.txt` |
| Magisk app status screen | **BLOCKED** (no resolvable launcher activity; package disappears after boot) | `root/magisk-status-UNAVAILABLE.md`, `root/magisk-app-info.png` |
| AlwaysStrong theoretical compatibility | **PASS for x86_64 TEE code; packaging gap for PIF** | `alwaysstrong/abi-matrix.txt`, `alwaysstrong/compatibility-review.md` |
| AlwaysStrong independent runtime evidence | **UNVERIFIED** | `alwaysstrong/independent-evidence-status.md` |
| AlwaysStrong independently verified attestation effect | **UNVERIFIED** | `alwaysstrong/independent-evidence-status.md` |

Status meanings follow the requested classifications. `CHECK_UNAVAILABLE` is
not a failure; `UNVERIFIED` is not a pass.

---

## 4. Phase A — stock Google Play baseline

### 4.1 Boot and identity

The stock AVD `integrity-stock` used the official Play Store image, 4 vCPU,
4096 MiB RAM, 1080x1920 at 420 dpi, cold boot with `-no-snapshot` and
`-wipe-data`. It reported:

- `sys.boot_completed=1`
- `ro.build.version.sdk=35`, `ro.build.version.release=15`
- `ro.product.cpu.abi=x86_64`
- `adb shell id` → `uid=2000(shell)`
- `pm path com.google.android.gms` and `pm path com.android.vending` both
  returned package paths
- Play Store and Play Services versions as listed above

The AVD config still reported `PlayStore.enabled=no` even though the image tag
was `google_apis_playstore` and the Play Store was installed and self-updated.
A later attempt to force `PlayStore.enabled=yes` is recorded as an
environmental failure below; the successful evidence comes from the run with
the image-provided value.

### 4.2 UI Test Actions control

Session `ba6fadebd87625b4f0276264` (Cloudflare Quick Tunnel) was controlled by
the external agent. The agent:

- captured the home screen and a fresh UI tree;
- launched the signed-out Play Store;
- opened the overflow menu and Settings;
- expanded About, read the Play Store version and “Device is not certified”;
- tapped the version row seven times, twice, with no Developer options;
- installed `dev.uitest.fixture` through `app.install`;
- launched it, inserted `Remote UI Test Actions input 2026-11-21`, clicked
  `APPLY CHANGE`, scrolled the 30-row list, and returned Home;
- waited 20 seconds and captured a further screenshot and tree to show the
  session was still live.

This is the evidence for “an external agent can interact with the runner and
emulator as if it were a normal computer.” It is not an ADB-only claim: every
listed interaction used the UI Test Actions API.

### 4.3 Genuine Play Integrity diagnostic

The documented Google procedure was followed as closely as the signed-out
Play Store allows:

`Play Store → profile/overflow → Settings → About → Play Store version (7 taps) → General → Developer options → Check integrity`

Observed:

- Settings was reachable through the overflow menu even when signed out.
- About showed `Play Store version 54.3.07-34 [0] [PR] 1022292552`.
- “Play Protect certification: Device is not certified”.
- After seven taps (07:22 UTC) and a second seven taps after relaunch
  (07:27 UTC), no `Developer options` entry and no `Check integrity` entry
  appeared.
- The self-update check said “Google Play Store is up to date.”
- Logcat contained `UNAUTHENTICATED: Request is missing required authentication
  credential` and an `IntegrityApiPersistentService` restart.

No account was created and no credential was used. No organization-approved
test account or Play Integrity test backend was available. The measurement is
therefore `CHECK_UNAVAILABLE`; the four verdict fields are `null`, not `false`.

Full record: [`stock/integrity-result.json`](stock/integrity-result.json).

---

## 5. Phase C — isolated rootAVD and Magisk

### 5.1 Isolation

The disposable AOSP guest was switched to airplane mode, `wlan0`/`eth0` were
brought down, and an `iptables OUTPUT` reject rule was applied while ADB was
temporarily root. `adb unroot` restored the ordinary shell. Verification:

- `post_unroot_shell_uid=2000`
- `network_isolated=yes` (ping to 8.8.8.8 failed)
- `http_isolated=yes` (HTTP probe failed)

The runner-side UI Test Actions transport remained independent of guest IP
traffic. Full output: [`root/network-isolation.txt`](root/network-isolation.txt).

### 5.2 rootAVD patch

Reviewed rootAVD commit:
`613caa44371f85e1a461bc030e07ddc2d71afe32`.

`rootAVD.sh ListAllAVDs` enumerated the installed image. The guest-side script
was run with the reviewed patch procedure and the staged official Magisk APK:

- Original ramdisk SHA-256: `ed02243242916aaa878b880f3eaa7ace1b44406747cdfecd585ad14ea0464fd5`
- Patched SHA-256: `660b722dcdc5e98920c4abf25faa5a79988ae4c9bd996a72783b814a2167e3a7`
- Patch exit: 0
- Original restore test: restoring the backup reproduced the original hash
  exactly; the patched image was then reinstalled
- Patch log contains a benign `line 1818: : Permission denied` from
  `update_lib_modules` because offline mode left `AVDIsOnline` unset; the same
  log shows the Magisk `init` replacement, `magisk.xz`/`init-ld.xz` additions,
  and successful repack.

Full log: [`root/patch.log`](root/patch.log), hashes:
[`root/ramdisk-hashes.txt`](root/ramdisk-hashes.txt).

### 5.3 Magisk runtime and root

After the first patched cold boot:

- `magisk -v` → `31.1:MAGISK:R`
- `magisk --path` → `/debug_ramdisk`
- `adb shell id` → UID 2000
- Magisk v31.1 no longer prompts for superuser access; it refuses until a
  policy is granted. The shell UID was granted through Magisk's own database
  (`policy=2`, the allow value), which is the documented CLI equivalent of the
  Superuser tab:
  `INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) VALUES (2000,2,0,1,1)`
- `/debug_ramdisk/su -c id` → `uid=0(root) gid=0(root) ... context=u:r:magisk:s0`

After a second cold boot, the same `su -c id` returned `uid=0(root)` again.
This establishes Magisk root persistence across cold boots.

The Magisk **app status screen** could not be captured. The APK declared
`com.topjohnwu.magisk.ui.MainActivity`, but the installed package had no
resolvable launcher activity, Settings offered no Open action, `am start`
returned “Activity class does not exist”, and after boot the package directory
was gone (`PackageManager: Package com.topjohnwu.magisk unavailable`). The
`su` path itself continued to work. This is recorded as `BLOCKED`, not as a
root failure.

### 5.4 Inert module loading

A harmless module (`integrity-inert-test`) wrote a timestamp and UID to
`/data/adb/inert-module-ran` from `post-fs-data.sh`; it changes no security
state. `magisk --install-module` first failed with “Incomplete Magisk install”
because `/data/adb/magisk` was empty. The official APK's runtime files were
then staged into `/data/adb/magisk`; the installer then succeeded
(`module_install_exit=0`) and the module directory was present before reboot.

After the next cold boot, `/data/adb/modules` was empty, the marker was absent,
and `/data/adb/magisk` had been cleared again. The module was not loaded.
This is a **FAIL** for module loading in this rootAVD/Magisk 31.1/API 35
configuration. It is also the prerequisite that would be needed for a module
such as AlwaysStrong to initialize, so an authorized AlwaysStrong runtime test
would need to solve this first.

---

## 6. Phase D — AlwaysStrong assessment

Reviewed: v1.0.6.1, commit `35b80223db44332f8262cb78453d561a36c97ea1`,
released 2026-11-12. Default ZIP SHA-256:
`560b69fb5b30999004f2a02bb2ffbe73567e61656bfb6ecf629c7a9803218636`.

### Published claims

- One-flash STRONG for Magisk / KernelSU / APatch (`README.md:21`).
- The default build “passes STRONG on most devices” (`README.md:57`).
- Every build installs on arm64-v8a, armeabi-v7a, x86 and x86_64; the
  `-inject` build has no x86 Zygisk; “On x86 use the default or the Lite build”
  (`README.md:69`).
- Android 10+; a Zygisk implementation is required; standalone Zygisk Next /
  ReZygisk / NeoZygisk is recommended over Magisk's built-in Zygisk.

**No explicit emulator, AVD, Android Studio, QEMU, BlueStacks, or Genymotion
compatibility statement was found** in the pinned README, docs, changelog, or
issue search.

### Architecture finding

The default release contains x86_64 TEE payloads
(`libTEESimulator.so`, `libinject.so`, `libsupervisor.so`), but its Zygisk
payload is ARM-only:

- `zygisk/arm64-v8a.so`
- `zygisk/armeabi-v7a.so`
- no `zygisk/x86.so`
- no `zygisk/x86_64.so`

`customize.sh` warns on x86_64 that the Play Integrity spoof will not load, yet
the README tells x86 users to use the default build. That is a packaging /
documentation inconsistency. `bin/x86_64/asfetch` is also absent; the shell
fallback is used.

### Four independent questions

1. **Architecture theoretically compatible?** The TEE half is present for
   x86_64; the default PIF Zygisk half is not. Theoretical PASS for the package
   and TEE code, with a concrete PIF packaging gap.
2. **All declared dependencies supported?** `UNVERIFIED` on this emulator.
   Android 15 meets the Android 10+ floor and Magisk 31.1 is installed, but
   Zygisk was not enabled and no standalone Zygisk implementation was tested.
3. **Runtime compatibility independently demonstrated?** `UNVERIFIED`. The
   module was not installed or executed.
4. **Genuine Play Integrity change independently demonstrated?** `UNVERIFIED`.
   No authorized attestation run and no live verifier call.

The module was **not** flashed, its `post-fs-data.sh`/`service.sh` were not
executed, and no attestation-modifying code was run against Google's live
verifier. This is the authorized-assessment boundary, not a claim that the
module fails.

Details: [`alwaysstrong/compatibility-review.md`](alwaysstrong/compatibility-review.md),
[`published-claims.md`](alwaysstrong/published-claims.md),
[`independent-evidence-status.md`](alwaysstrong/independent-evidence-status.md).

---

## 7. Failure handling and observed defects

### 7.1 Stock ADB authorization flakiness

The main stock run reached an authorized ADB shell and completed the session.
Two later Play Store boots (one with `PlayStore.enabled=yes`, one with `no`)
completed Android boot in ~27-28 seconds but stayed `adb: device unauthorized`
despite `-skip-adb-auth`. No UI session could start. This is an **environmental
reliability limitation** of the headless Play Store image, not a Play Integrity
result. The failed attempts are retained:

- [stock supplement run 44883707183](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44883707183)
- [stock system-information run 44884847559](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44884847559)

Consequence: the stock `system-information.png` target was not captured. Full
Android properties are in `stock/configuration.txt`, and the Play Store About
screenshot is `stock/play-store-about.png`.

### 7.2 UI Test Actions tree-source failure

On the AOSP `Settings > About emulated device` screen, `tree.snapshot` returned
HTTP 502 with `action_outcome_unknown` (request ID
`e0ac4b364d0346ccaad263057ce72eab`). `screenshot` and `pointer.scroll` /
`keyboard.press` continued to work on the same screen. This is a reproducible
UI Test Actions accessibility-source limitation, documented here with the
screenshot pair `root-screenshots/12-about-emulated-device.png` and
`14-about-emulated-device-scrolled.png`. No unpublished fix was merged.

### 7.3 Magisk app packaging

The Magisk v31.1 APK declares a launcher activity but the installed package
does not resolve one; the package directory disappears after a cold boot.
`app.launch` therefore returned 502/`action_outcome_unknown` twice, and the
status screen could not be captured. Root and `su` are unaffected. This is a
Magisk/emulator packaging finding, not a UI Test Actions failure.

### 7.4 Module removal

`magisk --install-module` succeeded only after staging the APK's runtime files
into `/data/adb/magisk`. The module was then removed at boot and its
`post-fs-data.sh` never ran. This is the main unresolved root-stack limitation
for module-based attestation research.

---

## 8. Deliverables

### GitHub Actions runs

| Phase | Run | Head SHA | Result |
|---|---|---|---|
| Runner preflight | [44876930009](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44876930009) | `2a76e5f82a39af14b7b297633d79d7d272b81395` | success |
| Stock Google Play baseline + UI session | [44879301592](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44879301592) | `e4df4e8bd9a876fc7134e47fc02908371294366d` | success |
| Root + su persistence + UI session | [44884770318](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44884770318) | `1cf056472a9b3c337134e1b932ae01c84f5d3bae` | success |
| Root module loading | [44886979581](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44886979581) | `c260f8dc60de085f47154781855af63cbd2bd71b` | success (module load FAIL) |
| AlwaysStrong source assessment | [44882516313](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44882516313) | `08acc1281b642b7781234d71d38171716c9d242c` | success |
| Stock supplement (environmental failure) | [44883707183](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44883707183) | `7f9eb429476f447aebfec30c7b0d154074d3faeb` | failure (ADB auth) |
| Stock system information (environmental failure) | [44884847559](https://github.com/ui-test-actions/ui-test-actions-consumer-acceptance/actions/runs/44884847559) | `3b6d428e588927ced6d60984475180cff47936bd` | failure (ADB auth) |

Earlier root runs that exposed the policy-value and app-launch issues are
retained in the Actions history; the final evidence above is from the runs
listed.

### Evidence archive

The repository evidence tree is committed at
`evidence/` on the experiment branch. The downloadable ZIP is produced by the
report workflow and linked in the chat message that accompanies this report.
The ZIP contains the same tree.

### Key screenshots

- Stock home: `stock/home-screen.png`
- Signed-out Play Store: `stock/play-store.png`
- Play Store About / “Device is not certified”: `stock/play-store-about.png`
- No Developer options after the documented taps: `stock/integrity-result.png`
- Fixture remote-control proof: `stock/fixture-after-click.png`
- Rooted AOSP home: `ui-test-actions/screenshots/root/01-root-session-start.png`
- Magisk app info (no Open action): `root/magisk-app-info.png`
- AOSP system information: `ui-test-actions/screenshots/root/12-about-emulated-device.png`

### Logs and configuration

- Runner: `runner/configuration.txt`, `runner/sdk-versions.txt`, `runner/acceleration.txt`
- Stock: `stock/configuration.txt`, `stock/play-versions.txt`, `stock/logcat.txt`, `stock/gms-dumpsys.txt`
- Root: `root/patch.log`, `root/ramdisk-hashes.txt`, `root/root-verification.txt`, `root/reboot-verification.txt`, `root/network-isolation.txt`, `root/module-install.txt`, `root/module-installed.txt`, `root/magisk-logcat.txt`
- AlwaysStrong: `alwaysstrong/version.txt`, `alwaysstrong/abi-matrix.txt`, `alwaysstrong/network-and-requirements.txt`

---

## 9. Unresolved questions

1. **Can a signed-in, organization-approved Play Store account unlock the
   Check integrity diagnostic on this stock emulator?** Not tested; no account
   was available and none was created. This is the direct path to genuine
   BASIC/DEVICE/STRONG/VIRTUAL labels.
2. **Does the Play Store diagnostic itself return labels on an uncertified
   emulator once unlocked?** Unknown; the menu was unreachable.
3. **Why does the Magisk v31.1 app package lose its launcher activity and its
   package directory across cold boots on this image?** Root and `su` survive,
   but the app and module runtime do not.
4. **Can the inert module be made to persist and execute on a different Magisk
   version or a complete app-driven setup?** Not tested; the v31.1 path was
   exhausted.
5. **Does AlwaysStrong boot and initialize on a rooted emulator with a working
   module subsystem and an x86_64 Zygisk payload?** `UNVERIFIED`; the current
   release has no x86_64 Zygisk payload.
6. **Does AlwaysStrong change a genuine Play Integrity verdict on an emulator?**
   `UNVERIFIED`; not executed, and no live verifier was contacted.
7. **Is the stock ADB authorization failure deterministic?** It occurred in 2 of
   3 later Play Store boots under the same flags; the first run succeeded. A
   deterministic headless-auth workaround was not established.

---

## 10. Cleanup and boundaries

- No production repository, release, or `main` branch was changed.
- No production Google account, private signing key, or personal credential was
  used.
- The private UI session token was generated on the runner, kept in a private
  artifact/local 0600 file, and is not part of the evidence tree.
- Emulators were shut down by the workflows; no long-running session remains.
- Experimental workflows are push-triggered because `workflow_dispatch`
  requires the workflow to exist on the default branch, and the experiment was
  not merged into `main`.
- The module was not executed against Google's live verifier.

---

## 11. Bottom line

- **Runner + emulator + remote agent control:** demonstrated.
- **Genuine Play Integrity verdicts:** not measurable in the signed-out stock
  configuration (`CHECK_UNAVAILABLE`), and not fabricated.
- **rootAVD + Magisk root:** demonstrated and persistent across cold boots.
- **Magisk module loading:** failed in this API 35 / Magisk 31.1 configuration.
- **AlwaysStrong:** source-level TEE architecture exists; the default release
  lacks x86_64 Zygisk; no independent runtime or attestation evidence exists.
