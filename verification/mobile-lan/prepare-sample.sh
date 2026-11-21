#!/usr/bin/env bash
set -euo pipefail

target="${1:?}"
producer="${2:?}"
digest="${3:?}"
[[ "$producer" =~ ^[1-9][0-9]{4,14}$ ]]
[[ "$digest" =~ ^[a-f0-9]{64}$ ]]
staging="$RUNNER_TEMP/mobile-lan-sample"
mkdir -p "$staging"
producer_workflow=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$producer" --jq \
  'select(.event == "workflow_dispatch" and .status == "completed") | .path')
test "$producer_workflow" = .github/workflows/mobile-lan-apps.yml
gh run download "$producer" --repo "$GITHUB_REPOSITORY" --pattern "p2pkit-sample-$target-*" --dir "$staging"
shopt -s nullglob
markers=("$staging"/*/SOURCE_COMMIT)
test "${#markers[@]}" = 1
package=$(dirname "${markers[0]}")
test "$(cat "$package/SOURCE_COMMIT")" = fd3cd74fcc82d342ee6c5a305f7ed15b0b7ed19d
asset=sample-app.zip
if [[ "$target" == android ]]; then asset=sample.apk; fi
(cd "$package" && test "$(shasum -a 256 "$asset")" = "$(cat SHA256SUMS)")
if [[ "$target" == android ]]; then
  cp "$package/sample.apk" "$staging/sample.apk"
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
