#!/usr/bin/env bash
# Source-level assessment of AlwaysStrong v1.0.6.1.
# This job never installs or executes the module and never contacts Google's
# live Play Integrity verifier. It records the reviewed commit, release hashes,
# ABI contents, declared dependencies, network endpoints, and published claims.
set -euo pipefail

out='evidence/alwaysstrong'
repo_dir="${RUNNER_TEMP}/AlwaysStrong"
zip_dir="${RUNNER_TEMP}/alwaysstrong-zips"
unzip_dir="${RUNNER_TEMP}/alwaysstrong-unzip"
commit='35b80223db44332f8262cb78453d561a36c97ea1'
tag='v1.0.6.1'
project='87739512'
base="https://gitlab.com/api/v4/projects/${project}/packages/generic/AlwaysStrong/${tag}"
mkdir -p "$out" "$zip_dir" "$unzip_dir"

rm -rf "$repo_dir"
git init -q "$repo_dir"
git -C "$repo_dir" remote add origin https://gitlab.com/Evokerr/AlwaysStrong.git
git -C "$repo_dir" fetch -q --depth 1 origin "$commit"
git -C "$repo_dir" checkout -q FETCH_HEAD
actual_commit="$(git -C "$repo_dir" rev-parse HEAD)"
test "$actual_commit" = "$commit"

for name in AlwaysStrong-${tag}.zip AlwaysStrong-${tag}-inject.zip AlwaysStrong-${tag}-nopif.zip; do
    curl -fsSL -o "${zip_dir}/${name}" "${base}/${name}"
done
sha256sum "${zip_dir}"/*.zip | sed "s#${zip_dir}/##" > "$out/release-assets.txt"

curl -fsSL "https://gitlab.com/api/v4/projects/${project}/releases/${tag}" \
    > "$out/gitlab-release.json"

unzip -q "${zip_dir}/AlwaysStrong-${tag}.zip" -d "$unzip_dir"

{
    echo "repository=https://gitlab.com/Evokerr/AlwaysStrong"
    echo "requested_commit=${commit}"
    echo "actual_commit=${actual_commit}"
    echo "commit_date=$(git -C "$repo_dir" show -s --format=%cI HEAD)"
    echo "tag=${tag}"
    echo "release_date=$(python3 -c 'import json;print(json.load(open("evidence/alwaysstrong/gitlab-release.json")).get("released_at",""))')"
    echo "default_zip=AlwaysStrong-${tag}.zip"
    echo "module_id=$(sed -n 's/^id=//p' "$unzip_dir/module.prop")"
    echo "module_name=$(sed -n 's/^name=//p' "$unzip_dir/module.prop")"
    echo "module_version=$(sed -n 's/^version=//p' "$unzip_dir/module.prop")"
    echo "module_versionCode=$(sed -n 's/^versionCode=//p' "$unzip_dir/module.prop")"
    echo "declared_minimum_android=10 (SDK 29), README.md:29"
} | tee "$out/version.txt"

{
    echo "=== native payloads in the default release ==="
    (cd "$unzip_dir" && find bin lib zygisk -type f 2>/dev/null | sort | while read -r f; do
        printf '%s | %s\n' "$f" "$(file -b "$f")"
    done)
    echo
    echo "=== module installer ABI branches ==="
    grep -nE 'case "\$ARCH"|ABI_DIR=|HAS_ZYGISK_SO|no PIF zygisk|PlayIntegrityFix inject-s is ARM-only|use the default build' \
        "$unzip_dir/customize.sh" || true
    echo
    echo "=== zygisk members in the default zip ==="
    unzip -l "${zip_dir}/AlwaysStrong-${tag}.zip" | grep -E 'zygisk/' || true
} | tee "$out/abi-matrix.txt"

{
    echo "=== direct references to emulator/virtual devices in the pinned tree ==="
    grep -RniE 'emulator|android studio|qemu|blue ?stacks|genymotion|virtual device|avd' \
        "$repo_dir" --include='*.md' --include='*.sh' --include='*.yml' --include='*.json' \
        --exclude-dir=.git || echo "none found"
    echo
    echo "=== x86 mentions in the pinned tree ==="
    grep -RniE 'x86|x86_64' "$repo_dir" --include='*.md' --include='*.sh' \
        --exclude-dir=.git | head -80 || true
} | tee "$out/emulator-mentions.txt"

{
    echo "=== network endpoints in the default release scripts ==="
    grep -rhoE 'https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' "$unzip_dir" \
        --include='*.sh' --include='*.prop' --include='*.txt' \
        | sed 's/[).,;]*$//' | sort -u || true
    echo
    echo "=== declared Zygisk/root requirements (README) ==="
    grep -nE 'Zygisk|Magisk|KernelSU|APatch|Android 10' "$repo_dir/README.md" | head -20 || true
} | tee "$out/network-and-requirements.txt"

cp ci/experiment/alwaysstrong/compatibility-review.md "$out/compatibility-review.md"
cp ci/experiment/alwaysstrong/published-claims.md "$out/published-claims.md"
cp ci/experiment/alwaysstrong/independent-evidence-status.md "$out/independent-evidence-status.md"

echo "alwaysstrong_assessment=complete"
