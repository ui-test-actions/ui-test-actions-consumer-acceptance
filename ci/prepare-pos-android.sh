#!/usr/bin/env bash
set -euo pipefail
dir="$RUNNER_TEMP/pos-android-input"
gh run download -R kira-manga/test 44218849282 -n pos-android-native-startup-api35-x86_64-16k-44218849282-1 -D "$dir"
test "$(cat "$dir/SOURCE-REVISION.txt")" = 46b89828ea133d9d5f7f802f2fa5546bbe3c31a6
printf '%s  %s\n' 9e8dab59bcd9bd4fa7e5f10c44f0091e7a3989552d11c06b10c0f41e2b7854a4 "$dir/ukkera-pos-testing.apk" | sha256sum -c
printf 'POS_APK=%s\n' "$dir/ukkera-pos-testing.apk" >> "$GITHUB_ENV"
