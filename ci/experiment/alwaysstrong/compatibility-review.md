# AlwaysStrong v1.0.6.1 — source-level compatibility review

## Scope

This review is static. The module was downloaded, hashed, unpacked, and
inspected on a GitHub-hosted runner. It was **not** installed on the emulator,
its `post-fs-data.sh` / `service.sh` were **not** executed, and Google's live
Play Integrity verifier was **not** contacted. Runtime and attestation effects
therefore remain `UNVERIFIED`.

## Identity

- Repository: https://gitlab.com/Evokerr/AlwaysStrong
- Commit: `35b80223db44332f8262cb78453d561a36c97ea1`
- Tag: `v1.0.6.1`, released 2026-11-12
- Module ID: `tricky_store` (deliberately reuses the TrickyStore module ID)
- Module version: `v1.0.6.1` / version code `1061`
- Default package SHA-256: `560b69fb5b30999004f2a02bb2ffbe73567e61656bfb6ecf629c7a9803218636`
- `-inject` SHA-256: `6ec79a881bc5e9ec1f89fe03cad9fe6c958e09f967fd8a800ef6575384fc8837`
- `-nopif` SHA-256: `f216d8511c99f3e066675c7dd72b34c60c9ad20d3e647b06f2bcfa96351b19ba`

## Declared platform and dependencies

| Requirement | Declared state | Review note |
|---|---|---|
| Android version | Android 10+ (SDK 29) | The experiment's API 35 images meet the floor. |
| Root manager | Magisk, KernelSU/SukiSU, or APatch | No root manager is bundled. |
| Zygisk | Required for the Play Integrity fingerprint hook | Magisk's built-in Zygisk is supported but the README recommends Zygisk Next / ReZygisk / NeoZygisk. |
| Keystore engine | Bundled TEESimulator-RS | Requires a keybox; the module fetches one on first Action. |
| Fingerprint engine | Bundled PlayIntegrityFork (default), PlayIntegrityFix inject-s, or none (Lite) | Default package is the Fork line. |
| Network | Required for first Action and hourly refresh | Keybox and fingerprint fetches are hard-bounded in the scripts. |

## ABI and payload review

The default release's native payloads are not uniform across architectures:

| Payload | arm64-v8a | armeabi-v7a | x86 | x86_64 |
|---|---:|---:|---:|---:|
| `libTEESimulator.so` | yes | yes | yes | yes |
| `libinject.so` / `inject` | yes | yes | yes | yes |
| `libsupervisor.so` / `supervisor` | yes | yes | yes | yes |
| `libcertgen.so` | yes | no | no | no |
| `zygisk/<abi>.so` | yes | yes | **no** | **no** |
| `bin/<abi>/aswatcher` | yes | yes | yes | yes |
| `bin/<abi>/asfetch` | yes | yes | **no** | **no** |

Consequences visible from the package alone:

1. The TEE/keystore half has x86_64 code and its installer accepts `x64`.
2. The default PlayIntegrityFork Zygisk payload does not exist for x86/x86_64 in
   this release. `customize.sh` warns that the Play Integrity spoof will not
   load on those ABIs, while the README's ABI paragraph tells x86 users to use
   the default build. These statements conflict.
3. `asfetch` is ARM-only. On x86/x86_64 the shell fallback is used for HTTPS
   fetches; the module's own comments say this is a helper, not the core.
4. The Lite (`-nopif`) build intentionally has no Zygisk payload at all and
   relies on a separately installed PIF.

## Attestation behavior visible in the scripts

The module is explicitly attestation-modifying. Static inspection found:

- TEESimulator-RS intercepts `keystore2` and builds attestation certificate
  chains from a configured keybox.
- PlayIntegrityFork injects a DEX into Play Services / DroidGuard to spoof
  `android.os.Build` fields and native properties.
- `post-fs-data.sh` and `service.sh` call `resetprop_if_diff` for boot-state
  properties including `ro.boot.verifiedbootstate`, `ro.boot.flash.locked`,
  `ro.boot.vbmeta.device_state`, `ro.boot.vbmeta.digest`, and verity state.
- The module refreshes a Pixel fingerprint and keybox on Action and hourly.

These are precisely the operations that must not be run against Google's live
verifier in an unauthorized assessment. They also mean a successful module
install would not, by itself, prove a genuine verdict change.

## Network access requirements

The first Action and the hourly service require network access. Observed
endpoints include:

- `http://evoker.qzz.io/key` — default keybox source (plain HTTP; override with
  `KEYBOX_BASE_URL`).
- `http://evoker.qzz.io/status` — status feed.
- `https://content-flashstation-pa.googleapis.com/...` — Pixel build metadata.
- `https://raw.githubusercontent.com/...`, `https://cdn.jsdelivr.net/...` —
  fingerprint/canary metadata fallbacks.
- `https://gitlab.com/Evokerr/AlwaysStrong/-/raw/main/update.json` — module
  update metadata.
- Telegram support/donation links are documentation only.

The plain-HTTP keybox default is a trust-boundary observation. The scripts hash
the downloaded payload before use, but transport confidentiality is not
provided by the default URL.

## Emulator-specific compatibility

No explicit emulator compatibility claim was found. The only emulator-adjacent
statements are:

- `build.sh`: "x86/x86_64 are emulator-only" in the context of native helper
  binaries.
- `README.md:69`: the ABI installation claim quoted above.
- `customize.sh`: the x86_64 "no PIF zygisk" warning.

The package therefore provides **architecture-level** evidence for x86_64 TEE
code, but not a documented, complete x86_64 Play Integrity path in the default
release. Whether a real emulator boots the module, starts TEESimulator, loads a
Zygisk payload, survives a reboot, and changes a genuine verdict is not
established by source review.

## Known failure modes reported by the developers

From `CHANGELOG.md`:

- v1.0.6.1 fixes a KernelSU-Next install failure when `/dev/tmp` is missing and
  makes optional helper extraction non-fatal.
- v1.0.6 notes that the default PIF can conflict with Play Services on some
  devices (Play Store crashes / account screen failures) and recommends the
  Lite build in that case.
- No emulator-specific boot failure or crash report was found in the reviewed
  release notes or issue search.

## Boundary

This document answers only the source-level questions. It does not claim that
AlwaysStrong works or fails on an emulator. The runtime and genuine-verdict
questions are marked `UNVERIFIED` in `independent-evidence-status.md`.
