# Lenovo E-ink Tablets (Rockchip RK3566) — Reverse-Engineering & Flashing Notes

> 🌏 Language: [**中文**](README.md) ｜ **English**

**Quick start**

1. Clone this repo
2. Power the tablet off, push the pin into the bottom pinhole, plug in USB to enter **Loader / Maskrom** (a Rockusb device appears in Device Manager)
3. Run `一键流程.cmd` → `[1]` to flash the root boot (`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`, verified bootable); `[2]` restore the stock boot / `[3]` full-firmware flash to unbrick
4. Boot and plug in USB (the boot defaults to adb): `adb install files\magisk_v28.1.apk` to install the Magisk manager (uninstall `com.topjohnwu.magisk` first on signature conflict)
5. Magisk → Modules → Install from storage → `模块\All-in-One.zip` → reboot — developer options, install restrictions and adb are all unlocked

---

This is the complete reverse-engineering and flashing record for two Lenovo e-ink tablets: **YOGA Paper (SP101FU)** and **QiTian Smart Paper (SP523FC)**. They share one hardware board **Louvre_3566_4G** (RK3566 / 4GB / 64GB / Android 11 · ZUI) as two market SKUs, but the firmware is **NOT interchangeable**: the boot image embeds model/region identifiers (SP523FC=CCN / SP101FU=PRC) that the system cross-checks at boot, and uboot SHA1-verifies the boot image — cross-flashing always fails.

What's inside: source-level analysis of the full boot chain — Android boot v2 layout, Rockchip uboot's SHA1 boot-id verification (`common/image-android.c`), the post-ramdisk **second/DTB section that bricks every naive repack**, loader partition read protection, the RK factory "UserMode" backdoor, ZUI's welded-shut developer options, Magisk root injection, and enabling adb by default — plus the automation: `build_boot.py` encodes every finding and repacks + recomputes the id in one step.

**SP523FC root verified working (2026-08-25), the root boot image boots.**

---

## 🎯 TL;DR for Rockchip researchers

> These findings are **not limited to these two Lenovo tablets** — they expose mechanisms common to **Rockchip Android devices (RK3566/RK3399/RK3568/RK3588, …)**. Every claim was derived from firmware / uboot source-level reverse engineering and verified against the factory images, so they port directly to other RK hardware and to your own repack tooling.

| Mechanism | Scope | Key point |
|---|---|---|
| RK boot image layout (header/kernel/ramdisk/second/dtb) | All Android 8+ RK devices | ramdisk offset = `(1+ceil(kernel_size/page))*page`; header page=2048; `id` at 0x240 |
| **Trailing second/DTB section** (RSCE container + 2 DTBs) | All RK boots with an RSCE container | **Dropping it = black screen, no boot**; must be preserved whole and shifted page-aligned |
| **uboot SHA1 boot-id check** (`common/image-android.c`) | RK uboots with `CONFIG_ANDROID_BOOT_IMAGE_HASH` | Any boot edit requires recomputing the id (algorithm below), else `return -EBADFD` |
| **`dtb_size` field-offset trap** | All Android boot v2 headers | `recovery_dtbo_offset` is a u64 → `dtb_size` actually lives at **0x670**; a standard-layout parser reads garbage |
| RK loader partition read protection (0xCC) | All RK loaders | boot/super/vbmeta etc. write-only; use `dd` after root for backups |
| **RK factory "UserMode" backdoor** | RK engineering/test firmware | `su --set-user-mode 2 --passwd rockchip` (mode1=adb, mode2=root) |
| uboot reads the BCB at offset **0x0** | RK uboot (recovery boot) | Not 0x4000; a stale `--wipe_all` at 0x4000 is simply ignored |
| Consumer vbmeta = `VERIFICATION_DISABLED` | RK consumer firmware | flags=0x2, AVB never rejects a modified boot; only fastboot unlock is blocked |
| CN-ROM adb stripping | Many domestic ROMs | USB HAL only honors charging/MTP + init.rc lacks the adb TCP trigger (below) |
| ZUI `isSupportDoubleList` developer-options lock | Lenovo ZUI family | `EinkUtils.isSupportDoubleList()` hardcoded true short-circuits the build-number tap |

> **Keywords**: rockchip root / RK3566 root / RK boot repack / rockchip boot repack / RK uboot image hash / ANDROID_BOOT_IMAGE_HASH / boot v2 dtb offset / RSCE resource container / Lenovo YOGA Paper SP101FU / QiTian Smart Paper SP523FC / ZUI isSupportDoubleList

---

## Devices

| SKU | Model | Market | Firmware | Status |
|---|---|---|---|---|
| YOGA Paper | SP101FU | CN / PRC | S001345 (2024-12-16) | Reverse-engineered; third-party project exists, see docs |
| QiTian Smart Paper | SP523FC | CN / education CCN | S001014 (2023-03-01) | ✅ **root verified** (2026-08-25) |

Hardware: RK3566 (quad Cortex-A55), 4GB RAM / 64GB eMMC, 10.3" e-ink, Android 11 · ZUI 13. Same board `Louvre_3566_4G`, two market SKUs, **incompatible firmware**.

---

## Repository structure

```
docs/
  SP101FU-YOGA-Paper/     RE + adb routes (README.md + README.en.md)
  SP523FC-QiTian/         root, adb, flashing flow (README.md + README.en.md)
build_boot.py             core RE tool: boot layout parse / cpio inject / preserve second+DTB / recompute SHA1 id (Python 3, stdlib only)
一键流程.cmd              SP523FC flashing menu (GBK, Windows double-click)
flash_boot.sh             bash equivalent (Git Bash), ~10 min device-wait loop with log
upgrade_tool.exe          Rockchip official command-line flash tool
adb.exe + DLL             bundled adb environment
img/                      firmware images (not in repo)
files/                    drivers / Magisk APK / MiniLoaderAll.bin (not in repo)
模块/All-in-One.zip       all-in-one Magisk module (developer options + adb + install unlock + wallpaper)
```

---

## Quick start

1. Power off, push the pin in the bottom pinhole, plug in USB to enter **Loader/Maskrom** (Rockusb appears in Device Manager)
2. Run `一键流程.cmd` → `[1]` to flash the root boot (`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`, verified bootable); `[2]` restore the stock boot / `[3]` full-firmware flash to unbrick
3. Boot and plug USB (the boot defaults to adb): `adb install files\magisk_v28.1.apk` (uninstall `com.topjohnwu.magisk` first on signature conflict)
4. Install `模块\All-in-One.zip` from Magisk → Modules → Install from storage, reboot — developer options, install restrictions and adb are all unlocked; a "SP523FC Helper" settings app appears

**Manual flashing (`upgrade_tool`)**:

```
upgrade_tool LD                             # detect device (Loader / Maskrom / No found)
upgrade_tool PL                             # show partition table
upgrade_tool WL 0x14000 boot.img            # write boot_a (LBA)
upgrade_tool WL 0x46000 boot.img            # write boot_b (LBA)
upgrade_tool DB files/MiniLoaderAll.bin     # Maskrom: download loader into device first
upgrade_tool RCI                            # read chip info (confirm loader is up)
upgrade_tool RD                             # reboot device
upgrade_tool uf update_nowaveform.img       # full-firmware flash (unbrick)
```

> In Maskrom (no loader), you must `DB` the `files/MiniLoaderAll.bin` first; only `WL` after `RCI` reports the chip.

> Fallback: if USB adb doesn't show up (some units' USB HAL only honors MTP), copy `模块/All-in-One.zip` to the device over MTP, install it in Magisk, reboot — the module force-enables adb as root (USB + WiFi `adb connect <ip>:5555`).

Full from-zero flow (drivers, adb authorization, app install) in [docs/SP523FC-QiTian/README.en.md](docs/SP523FC-QiTian/README.en.md).

---

## 🔬 Reverse-engineering deep dives

> Every claim below is grounded in firmware/code with the source cited; everything is reproducible.

### 1. Full boot image layout

Extracting the real boot partition (65,226,752 B) from the official RKFW package at offset `0x4df226` gives an Android boot v2 image with `page=2048`. Actual layout (SP523FC S001014):

```
0x000000 - 0x0007ff   header (page 0, hdr_v=2)
0x000800 - 0x1d7d000  kernel (kernel_size=0x1d7c010, page-aligned)
0x1d7d000 - 0x3de5a4c  ramdisk (ramdisk_size=0x2068a4c, gzip → cpio 70,404,096 B)
0x3de6000 - 0x3e18000  second section (second_size=0x32000=200KB, RSCE container w/ DTB#1)
0x3e18000 - 0x3e34800  DTB#2 section + tail padding
```

- **ramdisk offset = `(1 + ceil(kernel_size/page)) * page`**, `page=2048`. Using 4096 alignment gets it wrong
- All sections are located by *relative page alignment*, not absolute offsets — when repacking, move the tail whole to the page-aligned end of the new ramdisk
- Key header fields (parsed by `build_boot.py`):

| Offset | Field | Note |
|---|---|---|
| 0x008 | `kernel_size` (u32) | exact data size (not aligned) |
| 0x010 | `ramdisk_size` (u32) | the only field you change when repacking |
| 0x018 | `second_size` (u32) | declares the RSCE container (logo, rk-kernel.dtb) |
| 0x024 | `page_size` (u32) | =2048 |
| 0x240 | `id[20]` | target of the uboot SHA1 check (below) |
| 0x660 | `recovery_dtbo_offset` (u64) | **u64** — pushes `dtb_size` away from its standard position |
| 0x670 | `dtb_size` (u32) | actually at 0x670; a standard-layout parser reads garbage |

### 2. uboot SHA1 boot-id verification

Disassembly plus the Rockchip source (`common/image-android.c`, strings `"Hash from header"` / `"Hash real"` / `"ANDROID: Hash OK"`) confirm: **uboot SHA1-hashes the whole boot image and compares it against the header `id` field, rejecting with `return -EBADFD` on mismatch.** Algorithm (verified exactly against the factory id `7a4eb86d...`):

```
SHA1(
  kernel_data[pgsz : pgsz+kernel_size] + kernel_size(u32 LE)
  + ramdisk_data + ramdisk_size(u32 LE)
  + second_data + second_size(u32 LE)
  + recovery_dtbo_data(0 bytes) + recovery_dtbo_size(u32 LE)
  + dtb_data + dtb_size(u32 LE)
)
```

- Kernel data starts after the header page (`pgsz=2048`); each data block uses the exact size-field value (not page-aligned); the size field is appended *after* the data
- On mismatch uboot prints the three hashes and `return -EBADFD`
- **Any ramdisk edit requires recomputing the id at 0x240**, or the old id won't match the new content → no boot
- `compute_boot_id()` in `build_boot.py` does exactly this

### 3. Repack rules (the two fatal traps, solved in `build_boot.py`)

1. **You must preserve the trailing second/DTB section**: the stock boot has ~321KB after the ramdisk (`second_size=0x32000` + 2 DTBs). Every previous repack (including the old original.img) dropped it while the header still declared it → the device read a zeroed region → the kernel got no device tree and died before display init → **black screen, no response**. This is the first-layer root cause of every failed repack — independent of Magisk version, payload or prop changes.
2. **You must recompute the id**: still-no-boot after preserving the section = the uboot SHA1 check failing (second-layer root cause); recompute with the algorithm above.

Correct repack (`build_boot.py`): base = full stock boot → replace only the ramdisk (cpio-inject Magisk, or just change prop.default) → preserve the second/DTB section byte-for-byte, shifted to the page-aligned end of the new ramdisk → change only `ramdisk_size` → recompute `id`. The gzip is emitted with a factory-identical header (`FLG=0 MTIME=0 XFL=0 OS=3`). Magisk payloads come from a community-proven SP101FU package (V3zOF), with `.backup/.magisk`'s SHA1 regenerated against the true stock image.

Modes:

```
python build_boot.py magisk    # → boot_SP523FC_S001014_magisk_root_adbmtp.img (Magisk root + adb)
python build_boot.py noadb     # → boot_SP523FC_S001014_adbmtp_nomagisk.img (adb only, diagnostics)
python build_boot.py noop      # → boot_SP523FC_S001014_noop.img (same content, recompressed only; isolates whether recompression alone affects boot)
```

### 4. ZUI developer-options lockout

- Tapping the build number does nothing: `com.eink.settings.EinkUtils.isSupportDoubleList()` is hardcoded `return true`, and the first line of `BuildNumberPreferenceController.handlePreferenceTreeClick()` is `if (isSupportDoubleList() || ...) return false;` — the tap logic is short-circuited
- Search hides it: the search index of the developer-options page is gated by `DevelopmentSettingsEnabler.isDevelopmentSettingsEnabled()`
- The Activity is `android:enabled="false"` in the manifest, with a `DevelopmentSettingsDisabledActivity` placeholder; `am start` won't open it either
- **On Android 11 system-as-root the boot cannot touch the Settings DB**: recovery-in-boot has no root-level `init.rc`, normal boot only loads `/system/etc/init/*.rc` from the mounted system; anything under the ramdisk's `system/` is shadowed by the mounted system partition; the recovery-only rc (`init.recovery.rk30board.rc`) is never loaded in normal boot
- → The only working path: **root (Magisk) → install the module → unlock at boot as root**. The module runs (equivalent manual commands):

```
pm enable 'com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity'
settings put global development_settings_enabled 1
```

> ⚠️ **SP523FC (S001014) special case (re-checked 2026-08-25)**: the stock Settings already has `isSupportDoubleList()` returning **false**, and the developer-options Activity is not disabled — unlike SP101FU (S001345). So SP523FC needs **no Settings APK modification**, only `development_settings_enabled=1` (the module does this). See [docs/SP523FC-QiTian/README.en.md](docs/SP523FC-QiTian/README.en.md).

### 5. adb / USB chain

- The CN-ROM USB HAL **only honors charging/MTP**: `persist.sys.usb.config=adb` has no effect → USB adb is physically unavailable
- The system init.rc **lacks the `on property:persist.adb.tcp.port=* → start adbd` trigger**: setting the port alone never starts adbd
- Boot-level fix (prop.default): `persist.sys.usb.config=adb` + **`sys.usb.config=adb`** (starts adbd + the adb gadget at first-stage boot, bypassing the framework's MTP preference) + `persist.adb.tcp.port=5555` (fallback). **Caveat**: persist properties live in /data/property — clear /data once or the old `none` wins
- Fallback: the All-in-One module force-enables adb (USB + WiFi `adb connect <ip>:5555`) at boot as root

### 6. Recovery-in-boot, BCB, vbmeta, partitions

- **Recovery-in-boot**: the boot ramdisk carries AOSP recovery whose adbd is root — from recovery you can `adb shell`, `setprop persist.sys.usb.config adb`, then `reboot`; the property survives via /data/property. On SP101FU the recovery crashed on e-ink display init and auto-restarted, so it never worked on real hardware, but the principle holds
- **BCB location**: uboot reads the BCB at offset **0x0** (AOSP standard), **not** 0x4000 — a stale `boot-recovery --wipe_all` at 0x4000 was simply ignored, which is why the device always booted normally
- **vbmeta = VERIFICATION_DISABLED** (flags=0x2): AVB never rejects a modified boot; only fastboot unlock is blocked (`FAILgenerate unlock challenge fail`); loader direct-writes don't check unlock
- **Loader read protection**: `rl` on boot/super/vbmeta/cache/backup/metadata/logo returns all-0xCC; only misc/uboot/trust/security/waveform are readable → full backups aren't possible from the device side. **Root makes them trivial with `dd`**:

  ```
  adb shell su -c 'dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4096'
  ```

### 7. RK factory "UserMode" backdoor

The factory test app `DeviceTest.apk` references RK's service channel: `su --set-user-mode <n> --passwd rockchip` (mode1 = enable adb, mode2 = superuser), default password `rockchip`. Consumer firmware ships no `su` binary, so it's a dead end here — but worth probing on RK engineering/test firmware.

---

## Tooling

| Tool | Description |
|---|---|
| `build_boot.py` | Core RE tool: parse boot layout, cpio-inject Magisk, preserve second/DTB, recompute SHA1 id (Python 3, stdlib only, no third-party deps) |
| `一键流程.cmd` | SP523FC flashing menu: flash root boot / restore stock / full unbrick / info (GBK, Windows double-click) |
| `flash_boot.sh` | Bash equivalent (Git Bash), ~10 min device-wait loop and logging |
| `upgrade_tool.exe` | Rockchip official command-line flash tool (LD / PL / WL / RD / DB / RCI / uf) |
| `adb.exe` + DLL | bundled adb environment |

LBA partition map (SP523FC): `boot_a=0x14000`, `boot_b=0x46000`, `super=0x200800`. This loader can't write LP logical partitions (the table has only physical `super`, no `system`), so modifying the system means writing the whole super (`WL 0x200800 super_modified.sparse`).

---

## Notes

- The repo contains no firmware images or third-party binaries (see `.gitignore`) — only docs, scripts and RE findings
- Flashing is risky; data will be wiped; you brick it, you own it
- ⚠️ **Repacking boot requires preserving the trailing second/DTB section** + **recomputing the id** (see "deep dives")
- Mismatched firmware fails the boot self-check; the boot must match the system version
- Docs: Chinese `docs/*/README.md`, English `docs/*/README.en.md`

---

> **📜 Copyright**
> All content in this repository (code, docs, scripts) is for learning and reference only.
> **No commercial use, redistribution, modification or secondary distribution without the author's written permission.**
> Per GitHub Terms of Service, public repos may be forked, but default copyright law reserves all rights.
