# Ferrari KernelSU-Next + SuSFS boot pipeline

Builds a **separate** `boot.img` with [KernelSU-Next](https://github.com/pershoot/KernelSU-Next) (`dev-susfs`, v3.x) and [SuSFS](https://gitlab.com/simonpunk/susfs4ksu) **v2.2.x** on `gki-android12-5.10`. The daily ROM kernel (`kernel/oneplus/sm8450` / `ferrari-patches`) is left untouched.

## Build

From ROM root in WSL (`~/evo`). The kernel git hash in the pack-base `boot.img` **must** match the ROM on the phone (`uname -r`). The script refreshes `out/ksu-ferrari/working-rom/boot.img` from the newest `out/target/product/ferrari/EvolutionX-*.zip` when that zip is newer, and refuses a KSU-overwritten `product/boot.img` as the pack base.

```bash
cd ~/evo
bash device/realme/ferrari/ksu/build_ksu_boot.sh
bash device/realme/ferrari/ksu/build_ksu_boot.sh -j 16
bash device/realme/ferrari/ksu/build_ksu_boot.sh --clean
LUNCH_TARGET=evolution_ferrari-user bash device/realme/ferrari/ksu/build_ksu_boot.sh -j 16
```

A ROM-root `./build_ksu_boot.sh` wrapper is optional and is not in git.

Do not lunch a different variant than the last `./build_rom.sh`. Switching
`user` ↔ `userdebug` does not `rm -rf out/`, but Soong treats it as a new
product and rebuilds everything. The script now matches
`out/soong/soong.evolution_ferrari.variables` (`Debuggable`) unless you
override `LUNCH_TARGET`. The kernel `KERNEL_OBJ` is still shared, so the
kernel itself rebuilds when toggling `BUILD_KSU_BOOT`; frameworks should not.

Output:

- `out/ksu-ferrari/boot.img`
- `out/ksu-ferrari/Image`
- log under `build-logs/ksu-boot-*.log`

Pinned sources (see `apply-ksu-susfs.sh`):

- KernelSU-Next: `pershoot/dev-susfs` (v3.x + SuSFS; matches Manager **v3.3.0**)
- SuSFS: `gki-android12-5.10` tip (v2.2.x)

`BoardConfig.mk` uses `BUILD_KSU_BOOT=true` so kati picks `out/ksu-ferrari/kernel`. Clones live under `out/ksu-ferrari/src/` (not under `device/`).

## Flash

```bash
fastboot flash boot out/ksu-ferrari/boot.img
fastboot reboot
```

The image **must** be AVB-signed and padded to `BOARD_BOOTIMAGE_PARTITION_SIZE` (192 MiB). An unsigned `mkbootimg` output boots straight to recovery on ferrari. `build_ksu_boot.sh` always runs `avbtool add_hash_footer`.

Keep the matching ROM `vendor_boot` / `vendor_dlkm` from the **same kernel git hash**.
The kernel `Linux version` string (vermagic) must match those modules exactly —
including no extra `-dirty` suffix. `build_ksu_boot.sh` pins `.scmversion` to the
stock boot's `g<12-char-hash>` and packages the KSU `Image` into that stock
`boot.img` (ramdisk + AVB footer).

To restore a working boot from a ROM zip:

```bash
# payload.bin inside the zip → out/ksu-ferrari/working-rom/boot.img
fastboot flash boot out/ksu-ferrari/boot-restore.img
```

## Userspace

1. Install **KernelSU-Next Manager v3.3.0** (not v1.1.1):
   [KernelSU_Next_v3.3.0_33214-release.apk](https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.3.0/KernelSU_Next_v3.3.0_33214-release.apk)
   or the `-spoofed` APK from the same [v3.3.0 release](https://github.com/KernelSU-Next/KernelSU-Next/releases/tag/v3.3.0).
2. Install [sidex15/susfs4ksu-module](https://github.com/sidex15/susfs4ksu-module) (`v1.5.2+`, supports kernel SuSFS 2.x).

## Layout

| Path | Role |
|------|------|
| `apply-ksu-susfs.sh` | Fetch clones, create worktree, apply patches |
| `ksu.config` | `CONFIG_KSU` / `CONFIG_KSU_SUSFS*` fragment |
| `out/ksu-ferrari/src/` | Cloned KernelSU-Next + susfs4ksu (not under `device/`) |
| `out/ksu-ferrari/kernel` | Detached git worktree (patched) |

## Notes

- Kernel is **android12-5.10 GKI-line** (`5.10.x-gki`); SuSFS/KSU must be compiled in (not Magisk-style post-patch).
- `build_rom.sh` never enables KSU.
