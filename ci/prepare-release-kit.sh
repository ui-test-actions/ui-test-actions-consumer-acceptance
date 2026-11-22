#!/usr/bin/env bash
set -euo pipefail
stage="$RUNNER_TEMP/mrk-package"
evidence="$RUNNER_TEMP/mrk-evidence"
mkdir -p "$stage" "$evidence"
repo=Apdelrahman1911/mobile-release-kit
if [[ "$RUNNER_OS" == Linux ]]; then
  gh run download -R "$repo" 43719430392 -n linux-candidate-43719430392-attempt-1 -D "$stage"
  package="$stage/candidate/assembly/mobile-release-kit-desktop_0.1.4-1_amd64.deb"
  printf '%s  %s\n' 444f9e3b6f4e76bed2a10120513b047d56ed65509351a62c9edefec88904c57d "$package" | sha256sum -c
  dpkg-deb -f "$package" Package Version > "$evidence/package.txt"
  sudo apt-get -o Acquire::Retries=2 -q update
  sudo apt-get -o DPkg::Lock::Timeout=60 -o Acquire::Retries=2 install -y "$package"
  dpkg-query -W -f='${Status}\n' mobile-release-kit-desktop | tee -a "$evidence/package.txt"
  test -x /usr/bin/mobile-release-kit-desktop
else
  test "$(uname -m)" = arm64
  gh run download -R "$repo" 44886337931 -n macos-candidate-package-git-native-f62f6f04b84a5643c4b4e729b5b12eb8b87269cf-44886337931-1 -D "$stage"
  package="$stage/MobileReleaseKit.pkg"
  printf '%s  %s\n' 949e1f4f343669c7225bf9963082f813429c9c653b814dccbe6ba00e6aafbb64 "$package" | shasum -a 256 -c
  pkgutil --check-signature "$package" | tee "$evidence/package.txt"
  if ! sudo installer -verboseR -pkg "$package" -target / | tee -a "$evidence/package.txt"; then
    sudo tail -160 /var/log/install.log | grep -Ei 'MobileReleaseKit|mrk|package_script_service' > "$evidence/installer-diagnostics.txt" || true
    exit 1
  fi
  app=$(find /Applications -maxdepth 1 -iname '*mobile*release*kit*.app' -print -quit)
  test -n "$app" && test -d "$app"
  codesign --verify --deep --strict "$app"
  printf 'MRK_APP=%s\n' "$app" >> "$GITHUB_ENV"
fi
