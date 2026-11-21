#!/usr/bin/env bash
set -euo pipefail
stage=$(mktemp -d "$RUNNER_TEMP/parlor.XXXXXX")
gh run download 44848744079 -R parlor-game/parlor -n desktop-android-verification --dir "$stage"
bundle=$(find "$stage" -type f -name 'composeApp-release.aab')
test -n "$bundle"
printf '%s  %s\n' c8032952722e092ea9a3b44bcaacd8bba5e354795503513b5ca5f7071ca7194f "$bundle" | sha256sum --check --status
jar="$stage/bundletool.jar"
curl -fsSL --max-time 60 --retry 2 https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar -o "$jar"
printf '%s  %s\n' a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29 "$jar" | sha256sum --check --status
java -jar "$jar" dump manifest --bundle="$bundle" --xpath='/manifest/@android:versionName'
keytool -genkeypair -noprompt -keystore "$stage/emulator.jks" -storepass android -keypass android \
    -alias emulator -keyalg RSA -keysize 2048 -validity 2 -dname 'CN=Disposable Parlor Emulator'
java -jar "$jar" build-apks --bundle="$bundle" --output="$stage/app.apks" --mode=universal \
    --ks="$stage/emulator.jks" --ks-key-alias=emulator --ks-pass=pass:android --key-pass=pass:android
unzip -p "$stage/app.apks" universal.apk >"$stage/parlor.apk"
printf 'PARLOR_APK=%s\n' "$stage/parlor.apk" >> "$GITHUB_ENV"
