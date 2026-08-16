# android_device_realme_ferrari

Device tree for the **Realme GT2 Pro** (codename `ferrari`, RMX3301), running
**Evolution X 17** (Android 16/17, `cp2a` release branch) on a
Qualcomm **SM8450 (waipio)** platform with a **Synaptics S3908** touchscreen
and a 1440×3216 Samsung DSC command-mode panel.

This is the **main device tree** for the ferrari bring-up. All device-specific
fixes, the ROM-source patch set, and the build-time release configuration
originate here and are pushed to the `bubundas17` forks.

---

## Repo layout

| Path | Purpose |
| --- | --- |
| `evolution_ferrari.mk` / `lineage_ferrari.mk` | Product makefiles (Evolution X and LineageOS products) |
| `AndroidProducts.mk` | Lunch targets (`evolution_ferrari-userdebug`, `lineage_ferrari-userdebug`) |
| `BoardConfig.mk` | Board configuration |
| `patches/` | **ROM-source patch set** — the canonical storage for every change that is not device-local (see below) |
| `release/` | `cp2a` release-config contribution (aconfig overrides) |
| `overlay/`, `overlay-lineage/` | RRO overlays |
| `adb_keys` | Developer ADB keys authorized on userdebug builds |
| `extract-files.py` / `setup-makefiles.py` | Vendor blob extraction |
| `proprietary-files.txt` / `proprietary-firmware.txt` | Proprietary blob manifests |
| `lineage.dependencies` | Repo dependencies (sm8450-common, kernel, vendor) |
| `manifest.xml` | Repo manifest snippet for this device |

## Related repositories (all under `bubundas17`)

Current Android 17 / Evolution X 12.1 work is on `Evolution-X-v12.1-Android-17`.
The pre-repo-sync 12.0 tree is `Evolution-X-v12.0-Beta` and includes the
working UDFPS path.

- [android_device_oneplus_sm8450-common](https://github.com/bubundas17/android_device_oneplus_sm8450-common) — common device tree (audio config, sepolicy, blobs)
- [android_kernel_oneplus_sm8450](https://github.com/bubundas17/android_kernel_oneplus_sm8450) — kernel 5.10 (waipio)
- [android_kernel_oneplus_sm8450-devicetrees](https://github.com/bubundas17/android_kernel_oneplus_sm8450-devicetrees) — device trees
- [frameworks_base](https://github.com/Evolution-X/frameworks_base) — **upstream only, not forked**; all local changes live in `patches/`

## Building

Prerequisites: a full Evolution X source tree. Copy
`local_manifests/ferrari.xml` to `.repo/local_manifests/ferrari.xml` and
`repo sync` — device, kernel, and proprietary vendor trees all come from
`bubundas17` (no extract-files). Then set `TARGET_RELEASE=cp2a`.

```bash
# from the ROM root
export TARGET_RELEASE=cp2a

# apply the ROM-source patch set on top of upstream (repeat after every repo sync)
bash device/realme/ferrari/patches/apply-patches.sh

# build
. build/envsetup.sh
lunch evolution_ferrari-userdebug
m evolution
```

The resulting package is
`out/target/product/ferrari/EvolutionX-*-ferrari-*.zip`.

## Patch mechanism (`patches/`)

Every ROM-source change (anything outside the device-local repos) lives here
as a `git format-patch` patch file, so upstream updates never require
re-merging by hand.

| Directory | Repo patched | Patch count |
| --- | --- | --- |
| `patches/frameworks-base/` | `frameworks/base` | 16 |
| `patches/kernel-oneplus-sm8450/` | `kernel/oneplus/sm8450` | 2 |
| `patches/vendor-lineage/` | `vendor/lineage` | 1 |

Currently covers: UDFPS framework dimming and HBM-flash avoidance, discrete
brightness/volume slider haptics, monet shade rework, binary torch fallback,
service integration cleanup, Clang init fixes, **double-tap-to-wake
(`KEY_WAKEUP` on double tap)**, and ferrari vendor config tweaks.

- **Apply:** `bash device/realme/ferrari/patches/apply-patches.sh`
  — idempotent; skips already-applied commits; uses `git am --3way` so
  upstream context drift is auto-merged where possible; works from the
  detached state `repo sync` leaves behind.
- **Regenerate** after any new ROM-source commit:
  `bash device/realme/ferrari/patches/make-patches.sh`
- Patch bases (fork points): `frameworks/base` `9b016cee`, kernel
  `2863ca29^`, `vendor/lineage` `381d6e41^`. Update the SHAs in
  `make-patches.sh` only if the local branches are ever rebased.

## Change policy

Two kinds of changes, two routes — never mix them:

1. **Device-specific fixes** → commit and push directly to this repo
   (and the `sm8450-common` / devicetrees forks), branch
   `Evolution-X-v12.1-Android-17` (12.0 snapshot: `Evolution-X-v12.0-Beta`).
2. **Any other file (ROM sources)** → commit locally, regenerate the patch
   set with `make-patches.sh`, then commit and push the regenerated patches
   here. Never rely on loose unversioned ROM-tree edits.

Caveats:

- `vendor/oneplus/aconfig/` is not a git repo. Canonical files are in
  `patches/vendor-oneplus-aconfig/` and are copied by `apply-patches.sh`.
- `hardware/qcom-caf/sm8450/` is a container; git subprojects are patched
  via `make-patches.sh` / `apply-patches.sh`.
- `frameworks/base` is deliberately **not forked** — it tracks upstream
  Evolution X only.
- `kernel/oneplus/sm8450` may be pushed to `bubundas17` only together with a
  regenerated patch set, so the fork and the patches never diverge.

## Notable device-specific fixes

| Commit | Change |
| --- | --- |
| `d9c56e0` | Authorize developer ADB keys on userdebug builds |
| `19cc59a` | Enable UDFPS framework dimming layer |
| `05a87b3` | Avoid framework UDFPS HBM flash |
| `48da81f` | Disable LHDC codec via the `cp2a` release-config aconfig override (see below) |
| `75b94d0` | Device patch set and apply/regenerate scripts |

### LHDC / A2DP hardware offload

The QTI A2DP hardware-offload path (`btaudio_offload_if.so`) has no LHDC
parser, so LHDCv5 negotiated by earbuds such as the OnePlus Buds 4 plays
silent. The `release/` config contribution sets the Bluetooth aconfig flag
`lhdc_codec_support` to `DISABLED` in the `cp2a` release, forcing the stack to
fall back to AAC/SBC, which the DSP can encode. The A2DP offload properties
are enabled in `vendor/oneplus` / `sm8450-common`.

## Credits

Based on the upstream LineageOS `android_device_realme_ferrari`; Evolution X
product additions and all fixes maintained by `bubundas17`.
