#!/usr/bin/env bash
set -euo pipefail

target="${1:?}"
producer="${2:?}"
digest="${3:?}"
[[ "$producer" =~ ^[1-9][0-9]{4,14}$ ]]
[[ "$digest" =~ ^[a-f0-9]{64}$ ]]
staging="$RUNNER_TEMP/mobile-lan-sample"
mkdir -p "$staging"
case "$target:$producer" in
  android:44727058613|ios:44733760941) ;;
  *) printf '%s\n' "Unsupported cached build run." >&2; exit 1 ;;
esac
gh release download p2pkit-fixtures --repo "$GITHUB_REPOSITORY" --pattern "$target-*" --dir "$staging"
package="$staging"
mv "$staging/$target-source" "$package/SOURCE_COMMIT"
mv "$staging/$target-sha256" "$package/SHA256SUMS"
if [[ "$target" == android ]]; then
  mv "$staging/android-sample.apk" "$package/sample.apk"
else
  mv "$staging/ios-sample-app.zip" "$package/sample-app.zip"
fi
test "$(cat "$package/SOURCE_COMMIT")" = fd3cd74fcc82d342ee6c5a305f7ed15b0b7ed19d
asset=sample-app.zip
if [[ "$target" == android ]]; then asset=sample.apk; fi
case "$target" in
  android) expected=5526f8b958f8f86c37e818f0e766b15acee6f03564f0ad2d4ef2a514866cec8f ;;
  ios) expected=ad1a19ae223eb83f52e3b8ce6a0408f43861784fdf1be15774f370ce71f85607 ;;
esac
(cd "$package" && test "$(shasum -a 256 "$asset")" = "$expected  $asset")
if [[ "$target" == android ]]; then
  {
    echo LAN_DEVICE=emulator-5554
    echo LAN_APP_ID=dev.p2pkit.sample.android
  } >> "$GITHUB_ENV"
else
  test "$(uname -m)" = arm64
  ditto -x -k "$package/sample-app.zip" "$staging"
  app="$staging/p2pkit-sample.app"
  test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" = dev.p2pkit.sample
  executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Info.plist")
  otool -l "$app/$executable" > "$staging/load-commands.txt"
  grep -Eq 'sectname __entitlements|sectname __ents_der' "$staging/load-commands.txt"
  {
    printf 'LAN_DEVICE=%s\n' "$(cat "$RUNNER_TEMP/mobile-lan-preflight/device")"
    echo LAN_APP_ID=dev.p2pkit.sample
  } >> "$GITHUB_ENV"
  if [[ "${LAN_IOS_BACKEND:-visible}" == axe ]]; then
    asset=AXe-macOS-v2.1.1-universal.tar.gz
    curl --fail --silent --show-error --location --retry 3 \
      "https://github.com/cameroncooke/AXe/releases/download/v2.1.1/$asset" -o "$staging/$asset"
    printf '%s  %s\n' 8788838b1b32059d143cf06541b72fcaead85c16274457cdbff086510a5b17fa "$staging/$asset" |
      shasum -a 256 -c -
    tar -xzf "$staging/$asset" -C "$staging"
    axe=$(find "$staging" -name axe -type f -print -quit)
    test -x "$axe"
    printf 'LAN_AXE=%s\n' "$axe" >> "$GITHUB_ENV"
  fi
fi
