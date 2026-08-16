#!/bin/bash
#
# Applies the ferrari device patch set onto the ROM sources.
#
# Usage:
#   After `repo sync` (or any upstream update), run from the ROM root:
#       bash device/realme/ferrari/patches/apply-patches.sh
#
# Behavior:
#   - Repo dirs are matched to the patch dir names (frameworks/base,
#     kernel/oneplus/sm8450, vendor/lineage).
#   - A local branch "ferrari-patches" is reset to the synced manifest
#     revision (m/cnb, else evo/cnb) so a previous partial apply cannot
#     block new patches. Forks without those refs keep the current HEAD.
#   - Patches already applied (same commit subject in history) are skipped.
#   - If the newest patch in a directory is already in history (typical
#     for bubundas17 Evolution-X-v12.1-Android-17 forks, or a depth=1 clone of them),
#     the whole directory is skipped. Re-applying LFS pointer diffs onto
#     smudged binaries would conflict.
#   - Remaining patches are applied with `git am --keep-cr`, falling back
#     to `--3way` only if the straight apply fails. --3way needs blob SHAs
#     from the patch index lines; shallow clones after an upstream rebase
#     often lack those objects.
#   - vendor/oneplus/aconfig is not a git repo. The overlay in
#     patches/vendor-oneplus-aconfig/ is copied into place (LHDC off,
#     flashlight strength on for the cp2a release).
#
# Regenerate the patch files after any source change with
# device/realme/ferrari/patches/make-patches.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BRANCH="ferrari-patches"

declare -A REPO_PATHS=(
    [frameworks-base]="frameworks/base"
    [frameworks-libs-systemui]="frameworks/libs/systemui"
    [frameworks-native]="frameworks/native"
    [bionic]="bionic"
    [kernel-oneplus-sm8450]="kernel/oneplus/sm8450"
    [vendor-lineage]="vendor/lineage"
    [build-soong]="build/soong"
    [frameworks-av]="frameworks/av"
    [hardware-interfaces]="hardware/interfaces"
    [hardware-lineage-compat]="hardware/lineage/compat"
    [hardware-oplus]="hardware/oplus"
    [hardware-qcom-caf-sm8450-audio-primary-hal]="hardware/qcom-caf/sm8450/audio/primary-hal"
    [hardware-qcom-caf-sm8450-display]="hardware/qcom-caf/sm8450/display"
    [packages-apps-evolver]="packages/apps/Evolver"
    [packages-apps-settings]="packages/apps/Settings"
    [vendor-oneplus-sm8450-common]="vendor/oneplus/sm8450-common"
    [vendor-realme-ferrari]="vendor/realme/ferrari"
    [vendor-pixel-style]="vendor/pixel-style"
)

applied=0
skipped=0
failed=0

# First line of Subject: plus RFC 2822 wrapped continuations.
patch_subject() {
    awk '
        BEGIN { s = "" }
        /^Subject: / {
            sub(/^Subject: \[PATCH[^]]*\] /, "")
            s = $0
            next
        }
        s != "" && /^[ \t]/ {
            sub(/^[ \t]+/, " ")
            s = s $0
            next
        }
        s != "" { exit }
        END { print s }
    ' "$1"
}

subject_in_history() {
    local target="$1" subject="$2"
    [ -n "$subject" ] || return 1
    git -C "$target" log --format=%s HEAD | grep -qF "$subject"
}

for repo_dir in "$SCRIPT_DIR"/*/; do
    repo_name="$(basename "$repo_dir")"
    # Overlays / non-git trees: handled after the git-am loop.
    case "$repo_name" in
        vendor-oneplus-aconfig|opluscamera) continue ;;
    esac
    target="$ROOT/${REPO_PATHS[$repo_name]:-$repo_name}"

    if [ ! -e "$target/.git" ]; then
        echo "skip: $repo_name (no git repo at $target)"
        continue
    fi

    git -C "$target" am --abort >/dev/null 2>&1 || true

    # After repo sync, always recreate ferrari-patches from the synced
    # manifest revision so a previous partial apply cannot block new patches.
    start_ref=""
    if git -C "$target" rev-parse -q --verify m/cnb >/dev/null; then
        start_ref="m/cnb"
    elif git -C "$target" rev-parse -q --verify evo/cnb >/dev/null; then
        start_ref="evo/cnb"
    fi
    if [ -n "$start_ref" ]; then
        if ! git -C "$target" checkout -q -B "$BRANCH" "$start_ref"; then
            echo "FAIL: $repo_name: cannot reset $BRANCH to $start_ref (uncommitted changes?)"
            failed=$((failed + 1))
            continue
        fi
    else
        cur="$(git -C "$target" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        if [ "$cur" != "$BRANCH" ]; then
            if ! git -C "$target" checkout -q -B "$BRANCH"; then
                echo "FAIL: $repo_name: cannot create branch $BRANCH (uncommitted changes?)"
                failed=$((failed + 1))
                continue
            fi
        fi
    fi

    shopt -s nullglob
    patches=("$repo_dir"*.patch)
    shopt -u nullglob
    if [ ${#patches[@]} -eq 0 ]; then
        continue
    fi

    # Forks already on Evolution-X-v12.1-Android-17 (or a depth=1 clone) already
    # contain every patch in the tree. Re-applying LFS pointer diffs onto
    # smudged binaries conflicts. If the newest patch is in history, skip
    # the whole directory.
    last_subject="$(patch_subject "${patches[-1]}")"
    if subject_in_history "$target" "$last_subject"; then
        echo "already applied: $repo_name (tree includes: $last_subject)"
        skipped=$((skipped + ${#patches[@]}))
        continue
    fi

    for patch in "${patches[@]}"; do
        name="$(basename "$patch")"
        subject="$(patch_subject "$patch")"
        if subject_in_history "$target" "$subject"; then
            echo "already applied: $repo_name/$name"
            skipped=$((skipped + 1))
            continue
        fi
        # Several upstream OPLUS framework stubs use CRLF. Preserve carriage
        # returns while parsing mail patches so their context stays exact.
        if git -C "$target" am --keep-cr "$patch" \
                || { git -C "$target" am --abort >/dev/null 2>&1; git -C "$target" am --3way --keep-cr "$patch"; }; then
            echo "applied: $repo_name/$name"
            applied=$((applied + 1))
        else
            echo "FAILED: $repo_name/$name"
            git -C "$target" am --abort 2>/dev/null
            failed=$((failed + 1))
        fi
    done
done

# vendor/oneplus/aconfig is a Soong root-namespace overlay, not a git repo.
aconfig_src="$SCRIPT_DIR/vendor-oneplus-aconfig"
aconfig_dst="$ROOT/vendor/oneplus/aconfig"
if [ -d "$aconfig_src" ]; then
    mkdir -p "$aconfig_dst/com.android.bluetooth.flags" \
             "$aconfig_dst/com.android.systemui.flags"
    cp -a "$aconfig_src/Android.bp" "$aconfig_dst/Android.bp"
    cp -a "$aconfig_src/com.android.bluetooth.flags/." \
        "$aconfig_dst/com.android.bluetooth.flags/"
    cp -a "$aconfig_src/com.android.systemui.flags/." \
        "$aconfig_dst/com.android.systemui.flags/"
    echo "applied: vendor-oneplus-aconfig -> vendor/oneplus/aconfig"
    applied=$((applied + 1))
else
    echo "FAILED: vendor-oneplus-aconfig overlay missing at $aconfig_src"
    failed=$((failed + 1))
fi

echo
echo "Summary: $applied applied, $skipped skipped, $failed failed"
[ "$failed" -eq 0 ]
