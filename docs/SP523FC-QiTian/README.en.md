# QiTian Smart Paper (SP523FC) notes

Lenovo QiTian Smart Paper e-ink tablet; the firmware identifies as Lenovo SP523FC (board Louvre_3566_4G, same hardware as the YOGA Paper SP101FU above, different market SKU and firmware). Factory firmware S001014 (2023-03), also Android 11 · ZUI. These notes cover rooting it, getting adb, and unlocking the settings UI.

## The two packages and why they don't mix

Two packages came up during this work; they must not be mixed:

- `SP523FC_USR_S001014_2303011705_RK3566_CN` — the factory firmware for this device, model SP523FC, region CCN
- `SP101FU_USR_S001345_241216` — the YOGA Paper package, model SP101FU, region PRC

The systems are essentially the same code; the difference is model/version/region identity. The boot must match the system. Flashing the SP101FU boot onto an SP523FC machine trips the boot-time identity check — it refuses to boot with "current system version doesn't match hardware" (当前系统版本与硬件不匹配). Flashing back a matching boot works. So everything here is based on the SP523FC S001014 package.

## Where the ramdisk actually is in the boot image

Extracting the boot partition from `update_nowaveform.img` (RKFW format), the ramdisk offset computed from the header fields turned out to be wrong — the bytes there were high-entropy garbage that gzip/lz4/zstd/cpio all failed to open; I nearly wrote it off as encrypted. The real gzip stream is at `0x1d7d000`, 0x800 bytes earlier than the header-derived `0x1d7d800`, and decompresses to a 70MB cpio.

Why: the kernel_size field (30,916,624) is a bit short of the actual kernel bytes; the kernel plus signature region really runs to 0x1d7d000. So uboot does not locate the ramdisk by naive field alignment. When repacking, keep the original layout (kernel untouched, ramdisk still at 0x1d7d000, only update the ramdisk_size field) and the device finds the new ramdisk the same way. The boot partition is 100MB; the magisk-injected ramdisk grows from 33.98MB to 34.2MB and still fits.

Also confirmed the logo partition (logo.bmp, battery_*.bm) sits right after the boot image; it's not part of boot.

## Injecting Magisk root

Used Magisk v28.1's x86_64 magiskboot (runs natively on a Linux VM) to inject into the extracted ramdisk cpio:

```
magiskboot cpio ramdisk.cpio \
  "add 0750 init magiskinit" \
  "mkdir 0750 overlay.d" \
  "mkdir 0750 overlay.d/sbin" \
  "add 0644 overlay.d/sbin/magisk.xz magisk.xz" \
  "add 0644 overlay.d/sbin/stub.xz stub.xz" \
  "add 0644 overlay.d/sbin/init-ld.xz init-ld.xz" \
  "patch" "backup ramdisk.cpio.orig" \
  "mkdir 000 .backup" "add 000 .backup/.magisk config"
```

The payloads must be the arm64 ones (rename lib/arm64-v8a/libmagiskinit.so etc.). Don't stuff the x86_64 magiskboot in as magiskinit by mistake — it won't run on the device. After injection, gzip the cpio back and assemble the boot with the layout above.

## Default adb / developer mode

The ZUI settings here are locked the same way as SP101FU (developer options killed by isSupportDoubleList). What can be done from the boot side:

- `prop.default`: `persist.sys.usb.config=adb`, `ro.adb.secure=0`
- `init.recovery.rk30board.rc`: force `setprop persist.sys.usb.config adb` at early-fs (so a stale persisted value in /data can't override the default)
- a `devmode` boot service that, once the system is up, runs:
  - `pm enable com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity` (pm enable overrides the manifest-disabled activity)
  - `settings put global development_settings_enabled 1`

The "developer options" entry then shows up in the main settings list (that entry only checks the development_settings_enabled flag, not isSupportDoubleList); open it and toggle "USB debugging". adb is turned on manually, not forced.

## Unlocking the whole settings UI

isSupportDoubleList also locks app info, bluetooth, lockscreen and a lot of other entries, which the boot side can't fix. It needs the Settings app itself modified. The steps: decompile TC421_Settings.apk, flip `EinkUtils.isSupportDoubleList()` in smali from `const/4 v0, 0x1` to `const/4 v0, 0x0` (two bytes in the dex), change the developer options activity's `enabled="false"` to `true` in the manifest, re-sign, and replace the copy in system_a.

Re-signing with a test key is fine: the privapp whitelist entries for com.android.settings (`privapp-permissions-eink.xml`, `privapp-permissions-platform.xml`) have no `<signer>` restriction, so a new signature still gets the privileged permissions. The catch: the signature no longer matches the one recorded in /data/system/packages.xml, and PM ignores the new APK on that mismatch. Fix: erase userdata once after flashing the system (loader `EF` command) so PM rescans.

The modified system lives inside the whole super partition. This loader does not support LP logical-partition writes (`DI -s` says "No found system in the parameter"; the partition table only has the physical super, no system). So the super must be written whole: `WL 0x200800 super_modified.sparse` (the tool handles sparse; 3.5GB, roughly ten-plus minutes).

## Flashing workflow

`一键流程.cmd` (repo root) is the menu-driven script:

- `[1]` flash the modified system partition (super, wipes data) — unlocks settings
- `[2]` flash the root boot (Magisk)
- `[3]` flash back the stock boot
- `[4]` full package flash (stock, brick recovery)
- `[5]` help

To enter flash mode: power off, hold the pin in the small hole at the bottom, plug in USB. You may land in Loader or Maskrom:

- Loader: flash directly
- Maskrom: first `DB MiniLoaderAll.bin` to download a loader into the device (take MiniLoaderAll.bin from RKDevTool's Output/Android/Image, or from the official package); once RCI reads back chip info the loader is up, then proceed

## Partition read protection and backup

The loader read-protects boot/super/vbmeta etc. — `rl` returns all-0xCC, so no full on-device backup. It's a loader security limit with no public unlock (fastboot unlock is blocked by the signed challenge). Once rooted it doesn't matter; just dd from inside the system:

```
adb shell su -c 'dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4096'
```

Root is the simplest way around the partition lock for backups.

## Relation to SP101FU

Same hardware board (Louvre_3566_4G). SP101FU is the YOGA Paper (PRC), SP523FC is the QiTian Smart Paper (CCN); firmware is not interchangeable. The SP101FU findings (locked settings, recovery-in-boot, partition read protection) apply to SP523FC as well — only the packages and identity strings differ. See docs/SP101FU-YOGA-Paper/.
