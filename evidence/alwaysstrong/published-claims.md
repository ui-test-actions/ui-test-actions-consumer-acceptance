# AlwaysStrong v1.0.6.1 — published claims

Reviewed repository: https://gitlab.com/Evokerr/AlwaysStrong  
Reviewed commit: `35b80223db44332f8262cb78453d561a36c97ea1`  
Release tag: `v1.0.6.1` (released 2026-11-12)  
Default package: `AlwaysStrong-v1.0.6.1.zip`  
SHA-256: `560b69fb5b30999004f2a02bb2ffbe73567e61656bfb6ecf629c7a9803218636`

The quotes below are from that commit. They are developer claims, not
independent measurements.

| Claim | Source | Exact wording |
|---|---|---|
| One-flash STRONG result | `README.md:21` | "One-flash `STRONG` Play Integrity for Magisk / KernelSU / APatch." |
| Broad device success | `README.md:57` | "the default ... passes `STRONG` on most devices." |
| ABI coverage | `README.md:69` | "every build installs on arm64-v8a, armeabi-v7a, x86 and x86_64, but PlayIntegrityFix inject-s has no x86 zygisk — on x86 / x86_64 the `-inject` build can't spoof Play Integrity". "On x86 use the default or the Lite build." |
| Root managers | `README.md:23-27` | Magisk with Zygisk enabled, or KernelSU / SukiSU Ultra / APatch with a standalone Zygisk implementation. |
| Zygisk recommendation | `README.md:25` | A standalone Zygisk Next / ReZygisk / NeoZygisk "is recommended over Magisk's built-in Zygisk, which is more easily detected". |
| Android floor | `README.md:29` | "Android 10+ (SDK 29) is required." |
| First-run network behavior | `README.md:53` | "The first Action tap fetches a working keybox and a fresh Pixel fingerprint and restarts Play Integrity". |
| Hourly refresh | `README.md:82-88` | Hourly fingerprint/keybox refresh, automatic target updates, conflict-module disabling. |
| Explicit emulator support | — | **No explicit emulator, AVD, Android Studio, QEMU, BlueStacks, or Genymotion compatibility statement was found in the pinned README, docs, changelog, or issue search.** |

## What the package itself says about x86_64

The default release contains the TEE engine for all four ABIs:

- `lib/x86_64/libTEESimulator.so`
- `lib/x86_64/libinject.so`
- `lib/x86_64/libsupervisor.so`
- `lib/x86_64/libcertgen.so` is absent; the installer reports "TEESim installed (x86_64)" without native certgen.

The default release's Zygisk payload is ARM-only:

- `zygisk/arm64-v8a.so`
- `zygisk/armeabi-v7a.so`
- no `zygisk/x86.so`
- no `zygisk/x86_64.so`

`customize.sh` detects this and prints:

> "⚠️ no PIF zygisk for x86_64 (PlayIntegrityFork is ARM-only)"  
> "⚠️ TEE works, Play Integrity spoof won't"  
> "⚠️ use the default build for x86_64"

That last line is internally inconsistent with the package: the default build
is the one being installed and it also lacks the x86_64 Zygisk payload. This is
a documentation/packaging gap, not a runtime result.

## Interpretation boundary

These are published claims. No AlwaysStrong runtime was executed for this
experiment. The claims must not be read as independently verified emulator
compatibility or as a measured Play Integrity outcome.
