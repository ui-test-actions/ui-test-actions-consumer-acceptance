# AlwaysStrong v1.0.6.1 — independent evidence status

Four separate questions are reported independently. A source-level answer is
never promoted to a runtime result.

| # | Question | Status | Basis |
|---|---|---|---|
| 1 | Is the package architecture theoretically compatible? | **PASS (TEE half), packaging gap for PIF** | Default release contains `lib/x86_64/libTEESimulator.so`, `libinject.so`, `libsupervisor.so`; installer accepts `x64`. Default release has **no** `zygisk/x86_64.so`, so the PlayIntegrityFork spoof is not theoretically complete on x86_64. |
| 2 | Are all declared dependencies supported? | **UNVERIFIED on emulator** | Android 15 (API 35) meets the Android 10+ floor. Magisk 31.1 is installed in the root experiment, but Zygisk was not enabled and no Zygisk Next/ReZygisk/NeoZygisk was installed. The module's declared root-manager matrix was not exercised. |
| 3 | Has runtime compatibility been independently demonstrated? | **UNVERIFIED** | AlwaysStrong was not installed or executed. No boot, service, daemon, or module-loading evidence exists in this experiment. |
| 4 | Has a genuine Play Integrity change been independently demonstrated? | **UNVERIFIED** | No authorized attestation run; no live Play Integrity verifier call. The stock baseline itself returned `CHECK_UNAVAILABLE` because the Play Store developer diagnostic could not be unlocked without a signed-in account. |

## What would be required for an authorized runtime assessment

- Exact AlwaysStrong release and SHA-256 (`v1.0.6.1`, `560b69...` here).
- Exact emulator configuration, image revision, ABI, and API level.
- Magisk/KernelSU/APatch version, Zygisk implementation and version.
- Install log, TEESimulator daemon liveness, target list, keybox state.
- Cold-boot persistence evidence and crash/boot logs.
- A genuine verdict from an authorized test application and backend, kept
  separate from any predefined test responses.

Until those exist, the correct status for questions 2-4 is `UNVERIFIED`, not
PASS or FAIL.

## Non-claims

- The absence of an emulator mention in the README is not proof that the module
  fails on an emulator.
- The presence of x86_64 TEE libraries is not proof that the module reaches a
  Play Integrity verdict.
- The stock emulator's `CHECK_UNAVAILABLE` result is not an AlwaysStrong
  failure; it is a limitation of the signed-out Play Store diagnostic.
