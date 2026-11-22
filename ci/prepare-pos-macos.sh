#!/usr/bin/env bash
set -euo pipefail
test "$(uname -m)" = arm64
stage="$RUNNER_TEMP/pos-mac-input"
mkdir -p "$stage"
gh run download -R kira-manga/test 44235850072 -n pos-macos-dmg-arm64-44235850072-1 -D "$stage"
dmg="$stage/UkkeraPOS-1.0.0.dmg"
printf '%s  %s\n' 5c305c48bf8202dd97246a946959f785ddf07b9c2bfc99f24b74aa74fdc2cf93 "$dmg" | shasum -a 256 -c
grep -Fx 'original_source_revision=3683670b29bb4cac7af7f0afcccd84c50627dca7' "$stage/SOURCE-REVISION.txt"
mount="$stage/mounted"
mkdir "$mount"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount"
trap 'hdiutil detach "$mount"' EXIT
test -d "$mount/UkkeraPOS.app"
test ! -e /Applications/UkkeraPOS.app
codesign --verify --deep --strict "$mount/UkkeraPOS.app"
sudo ditto "$mount/UkkeraPOS.app" /Applications/UkkeraPOS.app
