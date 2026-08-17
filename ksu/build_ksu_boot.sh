#!/usr/bin/env bash
# Build a ferrari boot.img with KernelSU-Next + SuSFS (isolated kernel worktree).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$ROOT_DIR" != "/" && ! -f "$ROOT_DIR/build/envsetup.sh" ]]; do
    ROOT_DIR="$(dirname "$ROOT_DIR")"
done
if [[ ! -f "$ROOT_DIR/build/envsetup.sh" ]]; then
    echo "Error: could not find ROM root (build/envsetup.sh)" >&2
    exit 1
fi
KSU_DIR="$ROOT_DIR/device/realme/ferrari/ksu"
APPLY_SCRIPT="$KSU_DIR/apply-ksu-susfs.sh"
KERNEL_WT="${KSU_KERNEL_WORKTREE:-$ROOT_DIR/out/ksu-ferrari/kernel}"
ARTIFACT_DIR="${KSU_ARTIFACT_DIR:-$ROOT_DIR/out/ksu-ferrari}"
LOG_DIR="${LOG_DIR:-$ROOT_DIR/build-logs}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_LOG="$LOG_DIR/ksu-boot-$TIMESTAMP.log"
BUILD_JOBS="${BUILD_JOBS:-8}"
# Do not default to userdebug. Lunching a different TARGET_BUILD_VARIANT
# than the last ROM build (user ↔ userdebug) regenerates Soong and rebuilds
# the entire tree. Infer the last combo from soong.variables when present.
LUNCH_TARGET="${LUNCH_TARGET:-}"
CLEAN_WT=0
SKIP_FETCH=0
SKIP_APPLY=0

PRODUCT_OUT="$ROOT_DIR/out/target/product/ferrari"
KERNEL_IMAGE="$PRODUCT_OUT/obj/KERNEL_OBJ/arch/arm64/boot/Image"
# Prefer a known-good ROM boot (extracted zip) over product/boot.img, which
# m bootimage overwrites with a KSU kernel and the wrong ramdisk/vermagic.
STOCK_BOOT_IMG="${KSU_STOCK_BOOT:-}"
BOOT_PART_SIZE=201326592
AVB_KEY="$ROOT_DIR/external/avb/test/data/testkey_rsa4096.pem"

usage() {
    cat <<'EOF'
Usage: build_ksu_boot.sh [options]

Builds boot.img from an isolated kernel worktree with KernelSU-Next + SuSFS.
Does not modify kernel/oneplus/sm8450 (ferrari-patches).

Options:
  --clean         Recreate the kernel worktree before applying
  --skip-fetch    Do not update KSU/SuSFS clones
  --skip-apply    Assume worktree is already patched
  -j N            Parallel jobs (default: 8)
  -h, --help      Show help

Artifacts: out/ksu-ferrari/boot.img  out/ksu-ferrari/Image
Requires a working ROM boot.img (out/ksu-ferrari/working-rom/boot.img or product boot).
Lunches the last ROM combo (user vs userdebug) so Soong is not invalidated.
Override with LUNCH_TARGET=evolution_ferrari-userdebug if needed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN_WT=1; shift ;;
        --skip-fetch) SKIP_FETCH=1; shift ;;
        --skip-apply) SKIP_APPLY=1; shift ;;
        -j) BUILD_JOBS="${2:?}"; shift 2 ;;
        -j*) BUILD_JOBS="${1#-j}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR" "$ARTIFACT_DIR"
exec > >(tee -a "$BUILD_LOG") 2>&1

# True if this boot.img already contains a KSU kernel (m bootimage overwrites
# product/boot.img). Packing against that would nest KSU and skip the ROM ramdisk.
boot_img_is_ksu() {
    local img="$1"
    [[ -f "$img" ]] && grep -aqiE 'KernelSU|susfs' "$img"
}

payload_offset_in_zip() {
    python3 - "$1" <<'PY'
import struct, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
info = z.getinfo("payload.bin")
with open(sys.argv[1], "rb") as f:
    f.seek(info.header_offset)
    hdr = f.read(30)
    _sig, _ver, _flag, _method, _t, _d, _crc, _csz, _usz, nlen, elen = struct.unpack(
        "<IHHHHHIIIHH", hdr
    )
    print(info.header_offset + 30 + nlen + elen)
PY
}

# Keep working-rom in sync with the newest product zip so KSU vermagic matches
# the ROM actually flashed (Aug 12 working-rom + Aug 17 zip = bootloop).
refresh_working_rom_from_product_zip() {
    [[ -n "${KSU_STOCK_BOOT:-}" ]] && return
    local zip wr extractor off
    zip="$(ls -t "$PRODUCT_OUT"/EvolutionX-*.zip 2>/dev/null | head -1 || true)"
    [[ -n "$zip" && -f "$zip" ]] || return
    wr="$ARTIFACT_DIR/working-rom/boot.img"
    extractor="$ROOT_DIR/out/host/linux-x86/bin/ota_extractor"
    if [[ -f "$wr" && ! "$zip" -nt "$wr" ]]; then
        echo "Working-rom boot is current vs $(basename "$zip")"
        return
    fi
    if [[ ! -x "$extractor" ]]; then
        echo "Warning: ota_extractor missing; cannot refresh working-rom from $zip" >&2
        return
    fi
    echo "Refreshing working-rom boot from $(basename "$zip")"
    mkdir -p "$ARTIFACT_DIR/working-rom"
    off="$(payload_offset_in_zip "$zip")"
    "$extractor" -payload "$zip" -payload_offset "$off" \
        -output_dir "$ARTIFACT_DIR/working-rom" -partitions boot
    cp -f "$ARTIFACT_DIR/working-rom/boot.img" "$ARTIFACT_DIR/boot-restore.img"
}

resolve_stock_boot() {
    local candidates=(
        "${KSU_STOCK_BOOT:-}"
        "$ARTIFACT_DIR/working-rom/boot.img"
        "$ARTIFACT_DIR/boot-restore.img"
        "$PRODUCT_OUT/boot.img"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$c" ]] || continue
        if boot_img_is_ksu "$c"; then
            echo "Skipping KSU-tainted stock candidate: $c"
            continue
        fi
        STOCK_BOOT_IMG="$c"
        return
    done
    echo "Error: need a working ROM boot.img (extract the zip to out/ksu-ferrari/working-rom/)" >&2
    exit 1
}

# Fail closed if the phone is up and running a different kernel than the pack base.
warn_device_kernel_mismatch() {
    local adb state uname
    adb="${ADB:-/mnt/c/ProgramData/chocolatey/bin/adb.exe}"
    [[ -e "$adb" ]] || return 0
    state="$("$adb" get-state 2>/dev/null | tr -d '\r' || true)"
    [[ "$state" == "device" ]] || return 0
    uname="$("$adb" shell uname -r 2>/dev/null | tr -d '\r' || true)"
    [[ -n "$uname" ]] || return 0
    if [[ "$uname" != *"g${KSU_KERNEL_COMMIT}"* ]]; then
        echo "Error: phone kernel is $uname but stock boot is g${KSU_KERNEL_COMMIT}" >&2
        echo "Flash the matching ROM or extract that zip's boot.img into out/ksu-ferrari/working-rom/" >&2
        echo "Override with KSU_IGNORE_DEVICE=1 only if you know the phone is on this kernel." >&2
        if [[ "${KSU_IGNORE_DEVICE:-}" != "1" ]]; then
            exit 1
        fi
    fi
    echo "Phone kernel matches stock boot ($uname)"
}

# Linux version 5.10.246-gki-g0bb1376f1545 → commit 0bb1376f1545
stock_kernel_commit() {
    local unpack work ver
    unpack="$ROOT_DIR/out/host/linux-x86/bin/unpack_bootimg"
    work="$(mktemp -d)"
    "$unpack" --boot_img "$STOCK_BOOT_IMG" --out "$work" >/dev/null
    ver="$(python3 - <<PY
import re
d=open("$work/kernel","rb").read()
m=re.search(rb"Linux version [0-9.]+-gki-g([0-9a-f]{12})", d)
print(m.group(1).decode() if m else "")
PY
)"
    rm -rf "$work"
    printf '%s' "$ver"
}

refresh_working_rom_from_product_zip
resolve_stock_boot
STOCK_COMMIT="$(stock_kernel_commit)"
if [[ -z "$STOCK_COMMIT" ]]; then
    echo "Error: could not parse kernel git hash from $STOCK_BOOT_IMG" >&2
    exit 1
fi
export KSU_KERNEL_COMMIT="${KSU_KERNEL_COMMIT:-$STOCK_COMMIT}"
warn_device_kernel_mismatch

if [[ -z "$LUNCH_TARGET" ]]; then
    local_vars="$ROOT_DIR/out/soong/soong.evolution_ferrari.variables"
    lunch_variant=userdebug
    if [[ -f "$local_vars" ]]; then
        lunch_variant="$(python3 -c "import json; print('userdebug' if json.load(open(r'$local_vars')).get('Debuggable') else 'user')")"
    fi
    LUNCH_TARGET="evolution_ferrari-${lunch_variant}"
fi
# WITH_ADB_INSECURE must match the lunch combo. Setting it on a user tree
# (or leaving it set into the next ./build_rom.sh --release) changes
# product config and forces a full rebuild.
if [[ "$LUNCH_TARGET" == *-userdebug || "$LUNCH_TARGET" == *-eng ]]; then
    export WITH_ADB_INSECURE=true
else
    unset WITH_ADB_INSECURE
fi

echo "ROM root     : $ROOT_DIR"
echo "Kernel WT    : $KERNEL_WT"
echo "Stock boot   : $STOCK_BOOT_IMG"
echo "Stock commit : $KSU_KERNEL_COMMIT"
echo "Lunch        : $LUNCH_TARGET"
echo "Jobs         : $BUILD_JOBS"
echo "Log          : $BUILD_LOG"

if [[ "$CLEAN_WT" -eq 1 && -e "$KERNEL_WT" ]]; then
    echo "Removing existing worktree $KERNEL_WT"
    git -C "$ROOT_DIR/kernel/oneplus/sm8450" worktree remove --force "$KERNEL_WT" 2>/dev/null \
        || rm -rf "$KERNEL_WT"
fi

if [[ "$SKIP_APPLY" -eq 0 ]]; then
    apply_args=(--kernel-worktree "$KERNEL_WT" --kernel-commit "$KSU_KERNEL_COMMIT")
    [[ "$SKIP_FETCH" -eq 1 ]] && apply_args+=(--skip-fetch)
    [[ "$CLEAN_WT" -eq 1 ]] && apply_args+=(--force)
    bash "$APPLY_SCRIPT" "${apply_args[@]}"
else
    if [[ ! -f "$KERNEL_WT/.ksu-applied" ]]; then
        echo "Error: --skip-apply requires a patched worktree ($KERNEL_WT/.ksu-applied missing)" >&2
        exit 1
    fi
fi

cd "$ROOT_DIR"
if [[ ! -f build/envsetup.sh ]]; then
    echo "Error: build/envsetup.sh not found" >&2
    exit 1
fi
if [[ ! -f "$STOCK_BOOT_IMG" ]]; then
    echo "Error: need a working ROM boot.img at $STOCK_BOOT_IMG" >&2
    exit 1
fi

set +u
set +e
# shellcheck disable=SC1091
source build/envsetup.sh
envsetup_status=$?
set -e
set +u

if (( envsetup_status != 0 )); then
    echo "Error: envsetup failed ($envsetup_status)" >&2
    exit "$envsetup_status"
fi
if ! lunch "$LUNCH_TARGET"; then
    echo "Error: lunch failed for $LUNCH_TARGET" >&2
    exit 1
fi

mkdir -p "$ROOT_DIR/out/ksu-ferrari"
ln -sfn "$ROOT_DIR/kernel/oneplus/sm8450-modules" "$ROOT_DIR/out/ksu-ferrari/sm8450-modules"

rel_kernel_wt="${KERNEL_WT#"$ROOT_DIR"/}"
# Drop cached release string so .scmversion (no -dirty) is picked up.
rm -f "$PRODUCT_OUT/obj/KERNEL_OBJ/include/config/kernel.release" \
      "$PRODUCT_OUT/obj/KERNEL_OBJ/include/generated/utsrelease.h" \
      "$KERNEL_IMAGE"
echo "Building bootimage with BUILD_KSU_BOOT=true (kernel=$rel_kernel_wt)"
set +e
m bootimage -j"$BUILD_JOBS" BUILD_KSU_BOOT=true
build_status=$?
set -e

package_signed_boot() {
    local unpack mkboot avb work rb fp sp
    unpack="$ROOT_DIR/out/host/linux-x86/bin/unpack_bootimg"
    mkboot="$ROOT_DIR/out/host/linux-x86/bin/mkbootimg"
    avb="$ROOT_DIR/out/host/linux-x86/bin/avbtool"
    if [[ ! -x "$unpack" || ! -x "$mkboot" || ! -x "$avb" ]]; then
        echo "Error: need unpack_bootimg/mkbootimg/avbtool under out/host" >&2
        return 1
    fi
    work="$(mktemp -d "$ROOT_DIR/out/ksu-ferrari/pack.XXXXXX")"
    # Copy os_version / os_patch_level from the ROM boot. Hardcoding 2026-07
    # on a 2026-08 image makes the boot SPL older than system and the
    # device drops to recovery.
    local hdr os_ver os_pl
    hdr="$("$unpack" --boot_img "$STOCK_BOOT_IMG" --out "$work/unpack" --format=mkbootimg)"
    os_ver="$(printf '%s\n' "$hdr" | sed -n "s/.*--os_version \([^ ]*\).*/\1/p")"
    os_pl="$(printf '%s\n' "$hdr" | sed -n "s/.*--os_patch_level \([^ ]*\).*/\1/p")"
    cp -f "$KERNEL_IMAGE" "$work/unpack/kernel"

    echo "Packing boot header os_version=${os_ver:-17.0.0} os_patch_level=${os_pl}"
    "$mkboot" --header_version 4 \
        --os_version "${os_ver:-17.0.0}" \
        --os_patch_level "${os_pl:?missing os_patch_level from stock boot}" \
        --kernel "$work/unpack/kernel" \
        --ramdisk "$work/unpack/ramdisk" \
        --cmdline "" \
        --output "$ARTIFACT_DIR/boot.img"

    # Match the ROM boot.img AVB footer exactly. Hardcoding
    # rollback_index_location=4 (BoardConfig) diverges from the image the
    # build actually signs (location 0) and sends the device to recovery.
    local avb_info ril os
    avb_info="$("$avb" info_image --image "$STOCK_BOOT_IMG")"
    rb="$(printf '%s\n' "$avb_info" \
        | awk -F: '/^Rollback Index:/ {gsub(/ /,"",$2); print $2; exit}')"
    ril="$(printf '%s\n' "$avb_info" \
        | awk -F: '/^Rollback Index Location:/ {gsub(/ /,"",$2); print $2; exit}')"
    fp="$(printf '%s\n' "$avb_info" \
        | sed -n "s/.*com.android.build.boot.fingerprint -> '\\(.*\\)'/\\1/p")"
    sp="$(printf '%s\n' "$avb_info" \
        | sed -n "s/.*com.android.build.boot.security_patch -> '\\(.*\\)'/\\1/p")"
    os="$(printf '%s\n' "$avb_info" \
        | sed -n "s/.*com.android.build.boot.os_version -> '\\(.*\\)'/\\1/p")"

    local footer_args=(
        --image "$ARTIFACT_DIR/boot.img"
        --partition_name boot
        --partition_size "$BOOT_PART_SIZE"
        --algorithm SHA256_RSA4096
        --key "$AVB_KEY"
        --rollback_index "${rb:-0}"
        --prop "com.android.build.boot.os_version:${os:-17}"
        --prop "com.android.build.boot.fingerprint:${fp}"
        --prop "com.android.build.boot.security_patch:${sp}"
    )
    # Only pass location when non-zero; location 0 is avbtool's default and
    # keeps Minimum libavb version at 1.0 like the ROM boot.
    if [[ -n "${ril:-}" && "$ril" != "0" ]]; then
        footer_args+=(--rollback_index_location "$ril")
    fi
    "$avb" add_hash_footer "${footer_args[@]}"

    rm -rf "$work"
}

if [[ ! -f "$KERNEL_IMAGE" ]]; then
    echo "Error: kernel Image not produced at $KERNEL_IMAGE (m status=$build_status)" >&2
    exit 1
fi
# Do not use `strings | grep -q` under pipefail: grep -q closes the pipe early,
# strings gets SIGPIPE (141), and the check falsely fails.
if ! grep -aqiE 'KernelSU|susfs' "$KERNEL_IMAGE"; then
    echo "Error: Image lacks KernelSU/SuSFS markers; refusing to package" >&2
    echo "CONFIG_KSU in KERNEL_OBJ/.config:" >&2
    grep -E 'CONFIG_KSU|CONFIG_KSU_SUSFS' \
        "$PRODUCT_OUT/obj/KERNEL_OBJ/.config" 2>/dev/null || echo "  (none)" >&2
    echo "If hooks were wiped by checkout --force, re-run: ./build_ksu_boot.sh --skip-fetch -j $BUILD_JOBS" >&2
    exit 1
fi
if ! grep -aqF "g${KSU_KERNEL_COMMIT}" "$KERNEL_IMAGE"; then
    echo "Error: Image vermagic does not contain g${KSU_KERNEL_COMMIT} (modules will not load)" >&2
    python3 - <<PY
import re
d=open("$KERNEL_IMAGE","rb").read()
m=re.search(rb"Linux version [0-9][\x20-\x7e]{20,160}", d)
print("got:", m.group(0).decode() if m else "none")
PY
    exit 1
fi
if grep -aqF -- "-dirty" "$KERNEL_IMAGE"; then
    echo "Error: Image still has -dirty localversion; vendor modules will not load" >&2
    exit 1
fi

cp -f "$KERNEL_IMAGE" "$ARTIFACT_DIR/Image"
[[ -f "$KERNEL_WT/.ksu-applied" ]] && cp -f "$KERNEL_WT/.ksu-applied" "$ARTIFACT_DIR/ksu-applied.txt"

# Always package + AVB-sign from the KSU Image. A plain mkbootimg without the
# AVB hash footer boots straight to recovery on this device.
echo "Packaging AVB-signed boot.img (partition_size=$BOOT_PART_SIZE)"
package_signed_boot

echo
echo "KSU boot build completed."
ls -lh "$ARTIFACT_DIR/boot.img" "$ARTIFACT_DIR/Image"
sha256sum "$ARTIFACT_DIR/boot.img"
"$ROOT_DIR/out/host/linux-x86/bin/avbtool" info_image --image "$ARTIFACT_DIR/boot.img" | head -20
echo "Image contains KernelSU/SuSFS markers."
echo "Flash: fastboot flash boot $ARTIFACT_DIR/boot.img"
echo "Log  : $BUILD_LOG"

if (( build_status != 0 )); then
    echo "Note: m bootimage exited $build_status; used Image + AVB packaging fallback."
fi
