#!/bin/bash
#
# Regenerates the ferrari device patch set from the local ROM source repos.
#
# Usage (from the ROM root, after committing new local source changes):
#     bash device/realme/ferrari/patches/make-patches.sh
#
# Each repo is diffed against its fork point (the last upstream commit the
# local branch was created from). Update the base SHAs below if the local
# branches are ever rebased onto a newer upstream.
#
# If HEAD has no commits beyond the base (typical after `repo sync` before
# apply-patches), the existing patch dir is left untouched so unapplied
# ferrari patches are not deleted.
#
# The generated patches are applied with
# device/realme/ferrari/patches/apply-patches.sh

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="$ROOT/device/realme/ferrari/patches"

regenerate() {
    local repo="$1"
    local base="$2"
    local outdir="$3"
    if ! git -C "$ROOT/$repo" merge-base --is-ancestor "$base" HEAD; then
        echo "keep: $repo ($base is not an ancestor of HEAD; not wiping $outdir)"
        return
    fi
    local count
    count="$(git -C "$ROOT/$repo" rev-list --count "$base"..HEAD)"
    if [ "$count" -eq 0 ]; then
        echo "keep: $repo (HEAD is $base, leaving existing patches)"
        return
    fi
    rm -rf "$outdir"
    mkdir -p "$outdir"
    git -C "$ROOT/$repo" format-patch "$base"..HEAD -o "$outdir"
}

# Bases are current Evolution-X cnb (or the synced fork HEAD for bubundas17
# trees). Rebased ferrari stacks: frameworks/base, bionic, vendor/lineage,
# Evolver, Settings. Other dirs are kept unless those repos gain commits.
regenerate frameworks/base a1edf2bf5faf "$OUT/frameworks-base"
regenerate frameworks/libs/systemui bbdabb45579b "$OUT/frameworks-libs-systemui"
regenerate frameworks/native 81c26abb45 "$OUT/frameworks-native"
regenerate bionic e5a389d3d "$OUT/bionic"
regenerate kernel/oneplus/sm8450 9ed90e53e3ed "$OUT/kernel-oneplus-sm8450"
regenerate vendor/lineage 016e451d "$OUT/vendor-lineage"
regenerate build/soong 107339791680 "$OUT/build-soong"
regenerate frameworks/av 5e93d5c4f5c5 "$OUT/frameworks-av"
regenerate hardware/interfaces efaeff87c945 "$OUT/hardware-interfaces"
regenerate hardware/lineage/compat 9a7a916bb5d8 "$OUT/hardware-lineage-compat"
regenerate hardware/oplus 050f71d8af9b "$OUT/hardware-oplus"
regenerate hardware/qcom-caf/sm8450/audio/primary-hal 9f4dec53710a "$OUT/hardware-qcom-caf-sm8450-audio-primary-hal"
regenerate hardware/qcom-caf/sm8450/display 222878b523a9 "$OUT/hardware-qcom-caf-sm8450-display"
regenerate packages/apps/Evolver fdb4d6f5d454 "$OUT/packages-apps-evolver"
regenerate packages/apps/Settings f075f75c3e09 "$OUT/packages-apps-settings"
regenerate vendor/oneplus/sm8450-common 8023c6da2e99 "$OUT/vendor-oneplus-sm8450-common"
regenerate vendor/realme/ferrari f16f79eb52ee "$OUT/vendor-realme-ferrari"
regenerate vendor/pixel-style ff6f722e5797 "$OUT/vendor-pixel-style"

echo "Patches regenerated under $OUT"
