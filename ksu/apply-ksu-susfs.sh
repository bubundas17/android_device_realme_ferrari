#!/usr/bin/env bash
# Fetch KernelSU-Next (dev-susfs) + susfs4ksu and apply them to a kernel worktree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# Keep clones out of device/ — Make scans device/**/Android.mk and KernelSU's
# userspace/su conflicts with system/extras/su.
CACHE_DIR="${KSU_CACHE_DIR:-$ROM_ROOT/out/ksu-ferrari/src}"
KERNEL_WT="${KSU_KERNEL_WORKTREE:-$ROM_ROOT/out/ksu-ferrari/kernel}"
KERNEL_SRC_REPO="${KSU_KERNEL_SRC:-$ROM_ROOT/kernel/oneplus/sm8450}"
# Pin the worktree to the running ROM's kernel commit so vermagic matches
# vendor_boot modules. Default HEAD is wrong if the phone is on an older zip.
KERNEL_COMMIT="${KSU_KERNEL_COMMIT:-HEAD}"

KSU_REPO_URL="${KSU_REPO_URL:-https://github.com/pershoot/KernelSU-Next.git}"
# v3.x + SuSFS. next-susfs is deprecated v1 and does not match Manager v3.3.0.
KSU_REF="${KSU_REF:-dev-susfs}"
# origin/dev is required so Kbuild can compute KSU_VERSION = 30000 + rev-list.
KSU_VERSION_REF="${KSU_VERSION_REF:-dev}"
# Empty = branch tip. Set to a SHA to pin (the clone is a live symlink).
KSU_COMMIT="${KSU_COMMIT:-}"
SUSFS_REPO_URL="${SUSFS_REPO_URL:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_REF="${SUSFS_REF:-gki-android12-5.10}"
# Empty = branch tip (v2.2.x). v1.5.12 was only for next-susfs.
SUSFS_COMMIT="${SUSFS_COMMIT:-}"

SKIP_FETCH=0
FORCE=0

usage() {
    cat <<'EOF'
Usage: apply-ksu-susfs.sh [options]

Options:
  --kernel-worktree DIR   Kernel git worktree to patch (default: out/ksu-ferrari/kernel)
  --kernel-commit REV     Kernel commit/ref to check out (default: HEAD, or KSU_KERNEL_COMMIT)
  --skip-fetch            Use already-cloned trees under out/ksu-ferrari/src
  --force                 Re-apply even if .ksu-applied marker exists
  -h, --help              Show help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel-worktree)
            KERNEL_WT="${2:?}"
            shift 2
            ;;
        --kernel-commit)
            KERNEL_COMMIT="${2:?}"
            shift 2
            ;;
        --skip-fetch)
            SKIP_FETCH=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

MARKER="$KERNEL_WT/.ksu-applied"

hooks_present() {
    [[ -f "$KERNEL_WT/drivers/Kconfig" ]] \
        && grep -q 'drivers/kernelsu/Kconfig' "$KERNEL_WT/drivers/Kconfig" \
        && grep -q 'kernelsu' "$KERNEL_WT/drivers/Makefile" \
        && [[ -f "$KERNEL_WT/fs/susfs.c" ]] \
        && grep -q 'susfs' "$KERNEL_WT/fs/namespace.c" 2>/dev/null
}

fetch_repos() {
    mkdir -p "$CACHE_DIR"
    local ksu="$CACHE_DIR/KernelSU-Next"
    # Full history (not --depth 1): Kbuild sets KSU_VERSION from git rev-list.
    # A shallow next-susfs clone produced version 10200, which v3 Manager rejects.
    if [[ -d "$ksu/.git" ]]; then
        local cur
        cur="$(git -C "$ksu" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [[ "$cur" != "$KSU_REF" && "$cur" != "HEAD" ]]; then
            echo "KernelSU-Next branch is '$cur', replacing with $KSU_REF"
            rm -rf "$ksu"
        fi
    fi
    if [[ ! -d "$ksu/.git" ]]; then
        git clone -b "$KSU_REF" "$KSU_REPO_URL" "$ksu"
    elif [[ "$SKIP_FETCH" -eq 0 ]]; then
        git -C "$ksu" remote set-url origin "$KSU_REPO_URL"
        git -C "$ksu" fetch origin "$KSU_REF" "$KSU_VERSION_REF"
        git -C "$ksu" checkout -B "$KSU_REF" "origin/$KSU_REF"
    fi
    if [[ "$SKIP_FETCH" -eq 0 ]]; then
        git -C "$ksu" fetch origin "$KSU_VERSION_REF" 2>/dev/null || true
    fi
    if [[ -f "$ksu/.git/shallow" ]]; then
        git -C "$ksu" fetch --unshallow origin || true
    fi
    if [[ -n "$KSU_COMMIT" ]]; then
        git -C "$ksu" fetch origin "$KSU_COMMIT" 2>/dev/null || true
        git -C "$ksu" checkout -f "$KSU_COMMIT"
    fi
    # Drop leftover LKM Makefile rename / recursive setup.sh symlink so
    # in-tree Kbuild sees a clean kernel/ tree. The worktree compiles this
    # clone via a symlink, so a dirty clone changes the next Image even
    # when kernel hooks are left untouched.
    git -C "$ksu" reset --hard HEAD
    git -C "$ksu" clean -fdx
    KSU_COMMIT="$(git -C "$ksu" rev-parse HEAD)"

    if [[ ! -d "$CACHE_DIR/susfs4ksu/.git" ]]; then
        git clone "$SUSFS_REPO_URL" "$CACHE_DIR/susfs4ksu"
    elif [[ "$SKIP_FETCH" -eq 0 ]]; then
        git -C "$CACHE_DIR/susfs4ksu" fetch origin "$SUSFS_REF"
    fi
    if [[ -n "$SUSFS_COMMIT" ]]; then
        git -C "$CACHE_DIR/susfs4ksu" fetch origin "$SUSFS_COMMIT" 2>/dev/null || true
        git -C "$CACHE_DIR/susfs4ksu" checkout -f "$SUSFS_COMMIT"
    else
        if [[ "$SKIP_FETCH" -eq 0 ]]; then
            git -C "$CACHE_DIR/susfs4ksu" fetch origin "$SUSFS_REF"
        fi
        git -C "$CACHE_DIR/susfs4ksu" checkout -B "$SUSFS_REF" "origin/$SUSFS_REF"
        SUSFS_COMMIT="$(git -C "$CACHE_DIR/susfs4ksu" rev-parse HEAD)"
    fi
}

ensure_worktree() {
    if [[ ! -d "$KERNEL_SRC_REPO/.git" ]]; then
        echo "Error: kernel repo not found at $KERNEL_SRC_REPO" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$KERNEL_WT")"
    local rev
    rev="$(git -C "$KERNEL_SRC_REPO" rev-parse --verify "$KERNEL_COMMIT^{commit}")"
    if [[ -d "$KERNEL_WT/.git" || -f "$KERNEL_WT/.git" ]]; then
        echo "Using existing kernel worktree: $KERNEL_WT"
        local old
        old="$(git -C "$KERNEL_WT" rev-parse HEAD)"
        if [[ "$old" == "$rev" ]]; then
            echo "Already at $rev; leaving worktree (checkout --force would drop KSU hooks)"
            return
        fi
        git -C "$KERNEL_WT" checkout --detach --force "$rev"
        git -C "$KERNEL_WT" clean -fdx -e KernelSU-Next -e .scmversion
        echo "Kernel commit changed ($old -> $rev); will re-apply KSU patches"
        rm -f "$MARKER"
        return
    fi
    if [[ -e "$KERNEL_WT" ]]; then
        echo "Error: $KERNEL_WT exists but is not a git worktree" >&2
        exit 1
    fi
    echo "Creating kernel worktree at $KERNEL_WT from $KERNEL_SRC_REPO @$rev"
    git -C "$KERNEL_SRC_REPO" worktree add --detach "$KERNEL_WT" "$rev"
}

apply_patches() {
    local susfs="$CACHE_DIR/susfs4ksu/kernel_patches"

    if [[ -f "$MARKER" && "$FORCE" -eq 0 ]] && hooks_present; then
        echo "KSU/SuSFS already applied ($MARKER). Use --force to re-apply."
        return
    fi
    if [[ -f "$MARKER" && "$FORCE" -eq 0 ]]; then
        echo "Marker present but KSU Kconfig/Makefile hooks are missing; re-applying"
    fi

    # Do not run KernelSU-Next/kernel/setup.sh: it git-pulls the shared clone
    # (live symlink) and can float the driver sources under an already-patched
    # worktree. Wire Kconfig/Makefile ourselves.
    rm -rf "$KERNEL_WT/KernelSU-Next"
    ln -sfn "$CACHE_DIR/KernelSU-Next" "$KERNEL_WT/KernelSU-Next"

    pushd "$KERNEL_WT" >/dev/null
    if [[ "$FORCE" -eq 1 ]]; then
        git reset --hard HEAD
        git clean -fdx -e KernelSU-Next -e .scmversion
        ln -sfn "$CACHE_DIR/KernelSU-Next" "$KERNEL_WT/KernelSU-Next"
    fi

    ln -sfn ../KernelSU-Next/kernel drivers/kernelsu

    # v3 kernel/Makefile is an out-of-tree LKM wrapper and shadows Kbuild,
    # so in-tree `obj-$(CONFIG_KSU) += kernelsu/` would not produce kernelsu.o.
    local ksu_mk="$KERNEL_WT/KernelSU-Next/kernel/Makefile"
    if [[ -f "$ksu_mk" ]] && grep -q 'KDIR :=' "$ksu_mk"; then
        mv -f "$ksu_mk" "$KERNEL_WT/KernelSU-Next/kernel/Makefile.lkm"
        echo "Renamed out-of-tree KernelSU Makefile so in-tree Kbuild is used"
    fi

    # SuSFS kernel sources. pershoot dev-susfs already includes KSU-side SUSFS
    # hooks — do not apply 10_enable_susfs_for_ksu.patch.
    cp -a "$susfs/fs/susfs.c" fs/
    cp -a "$susfs/include/linux/susfs.h" include/linux/
    cp -a "$susfs/include/linux/susfs_def.h" include/linux/
    if [[ -f "$susfs/fs/sus_su.c" ]]; then
        cp -a "$susfs/fs/sus_su.c" fs/
    fi
    if [[ -f "$susfs/include/linux/sus_su.h" ]]; then
        cp -a "$susfs/include/linux/sus_su.h" include/linux/
    fi

    local susfs_patch
    susfs_patch="$susfs/50_add_susfs_in_gki-android12-5.10.patch"
    if [[ ! -f "$susfs_patch" ]]; then
        susfs_patch="$(find "$susfs" -maxdepth 1 -name '50_add_susfs_in_kernel*.patch' -print -quit)"
    fi
    if [[ -z "${susfs_patch:-}" || ! -f "$susfs_patch" ]]; then
        echo "Error: no SuSFS 50_add_susfs patch under $susfs" >&2
        popd >/dev/null
        exit 1
    fi
    local dry
    dry="$(mktemp)"
    if patch -p1 --forward --dry-run < "$susfs_patch" >"$dry" 2>&1; then
        patch -p1 --forward < "$susfs_patch"
    elif grep -qiE 'previously applied|Reversed' "$dry"; then
        echo "SuSFS kernel patch already applied"
    else
        echo "Error: SuSFS kernel patch does not apply cleanly" >&2
        cat "$dry" >&2
        rm -f "$dry"
        popd >/dev/null
        exit 1
    fi
    rm -f "$dry"

    if [[ ! -f drivers/kernelsu/Kconfig ]]; then
        echo "Error: drivers/kernelsu/Kconfig missing after setup" >&2
        popd >/dev/null
        exit 1
    fi
    if ! grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig; then
        sed -i '$i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
        echo "Sourced drivers/kernelsu/Kconfig"
    fi
    if ! grep -q 'kernelsu' drivers/Makefile; then
        printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
        echo "Added kernelsu to drivers/Makefile"
    fi
    popd >/dev/null

    {
        echo "ksu_repo=$KSU_REPO_URL"
        echo "ksu_ref=$KSU_REF"
        echo "ksu_commit=${KSU_COMMIT:-$(git -C "$CACHE_DIR/KernelSU-Next" rev-parse HEAD)}"
        echo "susfs_repo=$SUSFS_REPO_URL"
        echo "susfs_ref=$SUSFS_REF"
        echo "susfs_commit=$SUSFS_COMMIT"
        echo "kernel_commit=$(git -C "$KERNEL_WT" rev-parse HEAD)"
        echo "applied_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$MARKER"

    echo "Applied KSU-Next ($KSU_REF ${KSU_COMMIT:0:12}) + SuSFS ($SUSFS_COMMIT) to $KERNEL_WT"
}

# Match the running ROM's vermagic. Uncommitted KSU patches otherwise append
# -dirty and vendor_boot modules refuse to load (logo, then recovery).
pin_localversion() {
    local short
    short="$(git -C "$KERNEL_WT" rev-parse --short=12 HEAD)"
    # scripts/setlocalversion cats this file and skips git -dirty detection.
    printf '%s' "-g${short}" > "$KERNEL_WT/.scmversion"
    echo "Pinned kernel localversion to -g${short} (no -dirty)"
}

# When KERNEL_SRC is out/ksu-ferrari/kernel, external module Makefiles resolve
# ../sm8450-modules relative to the worktree parent.
ensure_modules_symlink() {
    local link="$ROM_ROOT/out/ksu-ferrari/sm8450-modules"
    local target="$ROM_ROOT/kernel/oneplus/sm8450-modules"
    mkdir -p "$(dirname "$link")"
    ln -sfn "$target" "$link"
}

ensure_worktree
if [[ -f "$MARKER" && "$FORCE" -eq 0 ]] && hooks_present; then
    echo "KSU/SuSFS already applied ($MARKER); not fetching (clone is a live symlink)."
else
    fetch_repos
    apply_patches
fi
pin_localversion
ensure_modules_symlink
