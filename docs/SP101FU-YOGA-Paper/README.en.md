# YOGA Paper (SP101FU) notes

Lenovo YOGA Paper e-ink tablet, model SP101FU, RK3566 / 4GB / 64GB, Android 11 · ZUI 13. These are my notes from reverse-engineering and flashing this device, mostly for my own reference but hopefully useful to others.

## Why developer options can't be opened

The ZUI settings app (TC421_Settings) has the developer options entry locked down with no visible path in the UI:

- Tapping the build number does nothing. Decompiling `TC421_Settings.apk` shows `com.eink.settings.EinkUtils.isSupportDoubleList()` is hardcoded to `return true`, and the first line of `BuildNumberPreferenceController.handlePreferenceTreeClick()` is `if (EinkUtils.isSupportDoubleList() || ...) return false;`. The tap logic is short-circuited in code; no countdown, no feedback, nothing.
- Search doesn't find developer options either. The search index for the developer options page is gated by `DevelopmentSettingsEnabler.isDevelopmentSettingsEnabled()`, so it's not indexed while the flag is off.
- The developer options activity (`com.android.settings.Settings$DevelopmentSettingsDashboardActivity`) is `android:enabled="false"` in the manifest, with a `DevelopmentSettingsDisabledActivity` placeholder. Even `am start` won't launch it.

So on this build there is no software path to developer options or adb without root, or without a persistent replacement settings app.

## What isSupportDoubleList is

It's the master switch for ZUI's simplified "double list" e-ink UI, used all over the app (app info, lockscreen, bluetooth, etc. get cut by it). That's why the S001345 settings differ so much from stock AOSP. To unlock the UI you need to make this function return false and replace the system settings app.

## No su in the system

There is no `su` binary anywhere in system/vendor/product/odm/system_ext or the boot ramdisk. The factory test app DeviceTest.apk references RK's "user mode" switch (mode1 enables adb, mode2 super user, via `su --set-user-mode <n> --passwd rockchip`), but su itself doesn't exist, so that after-sales path doesn't work on S001345.

## A no-flash path to adb: recovery

S001345 is recovery-in-boot; the boot ramdisk carries stock AOSP recovery (adbd in sideload/shell is root). Once in recovery:

```
adb devices
adb shell          # root here
setprop persist.sys.usb.config adb
reboot
```

The persist property lands in /data/property and survives reboot, so the system comes up with USB in adb mode. `ro.adb.secure=1` shows the "allow USB debugging" prompt on screen; just tap it.

Two ways into recovery:

- uboot key combo ("boot mode: recovery (key)")
- loader writes the BCB in the misc partition ("boot mode: recovery (usb)")

When writing misc, note that uboot reads the BCB at offset 0x0 (standard AOSP position), not 0x4000. An old backup had a stale `boot-recovery --wipe_all` at 0x4000, but uboot never reads it, which is why the device kept booting normally. Write the BCB at 0x0, and clear the 0x4000 leftovers too.

In practice the device does enter recovery with a correct BCB, but recovery crashes on the e-ink display init and auto-reboots, so it can't stay. That route didn't work on the real device.

## Misc findings

- vbmeta is VERIFICATION_DISABLED (flags=0x2), so AVB partition hash verification is off; a modified boot won't be rejected by AVB. What's locked is fastboot unlock (uboot says `FAILgenerate unlock challenge fail`); loader direct writes don't check unlock.
- The loader read-protects boot/super/vbmeta/cache/backup/metadata/logo etc. — `rl` returns all-0xCC fill. Only misc/uboot/trust/security/waveform can be read. Full on-device backup is therefore not possible; the reliable restore medium is the stock flash package itself.
- On this build, boot ramdisk has `persist.sys.usb.config=none`, `ro.adb.secure=1`, `ro.secure=1`, `ro.debuggable=0`. USB defaults to MTP, not adb; the community claim "adb works right after flashing" needs verification.
