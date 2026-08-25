# YOGA Paper（SP101FU）折腾记录

联想 YOGA Paper 墨水屏平板，型号 SP101FU，RK3566 / 4GB / 64GB，Android 11 · ZUI 13。这篇文章记录的是围绕这台机器做过的逆向和刷机尝试，主要是给自己备忘，也希望能帮到同样折腾这台机器的人。

## 为什么开发者选项打不开

国行 ZUI 定制的设置应用（TC421_Settings）把开发者选项入口整个焊死了，表面上没有任何入口：

- 连点版本号没反应。反编译 `TC421_Settings.apk` 后发现，`com.eink.settings.EinkUtils.isSupportDoubleList()` 被硬编码成 `return true`，而 `BuildNumberPreferenceController.handlePreferenceTreeClick()` 第一行就是 `if (EinkUtils.isSupportDoubleList() || ...) return false;`。连点逻辑被代码写死短路，点多少次都不会动，连倒计时提示都没有。
- 搜索里也搜不到开发者选项。开发者选项页的搜索索引被 `DevelopmentSettingsEnabler.isDevelopmentSettingsEnabled()` 挡住，开关是关的就不索引。
- 开发者选项的 Activity（`com.android.settings.Settings$DevelopmentSettingsDashboardActivity`）在 manifest 里是 `android:enabled="false"`，另外还有个 `DevelopmentSettingsDisabledActivity` 占位，直接 `am start` 也打不开。

也就是说，在 S001345 这个版本的设置里，没有任何软件路径能打开开发者选项或者 adb，除非 root 或者让替换的设置持久生效。

## isSupportDoubleList 是什么

它是 ZUI 墨水屏「双列表简化 UI」的总开关，全应用到处都在用（App 信息、锁屏、蓝牙等都被它砍掉）。这也是 S001345 的设置和原生 AOSP 差异特别大的原因。想解锁 UI 就得把这个函数改成返回 false，然后替换系统里的设置应用。

## 系统里没有 su

整个 system/vendor/product/odm/system_ext 和 boot ramdisk 里都没有 `su` 二进制。虽然出厂测试应用 DeviceTest.apk 里引用了 RK 的「用户模式」切换（mode1 开 adb、mode2 超级用户，命令是 `su --set-user-mode <n> --passwd rockchip`），但 su 本体不存在，这条售后通道在 S001345 上走不通。

## 不开机也能开 adb 的路：Recovery

S001345 是 recovery-in-boot，boot 的 ramdisk 里带着标准 AOSP recovery（sideload 和 shell 的 adbd 是 root）。进 recovery 后可以：

```
adb devices
adb shell          # 此时是 root
setprop persist.sys.usb.config adb
reboot
```

persist 属性会写进 /data/property，跨重启存活，重启后系统 USB 就是 adb 了。`ro.adb.secure=1` 会在屏幕上弹「允许 USB 调试」，点一下就行。

进 recovery 有两种方式：

- uboot 支持按键进 recovery（"boot mode: recovery (key)"）
- 用 loader 写 misc 分区的 BCB 进 recovery（"boot mode: recovery (usb)"）

写 misc 的时候要注意，uboot 读的是 0x0 处的 BCB（AOSP 标准位置），不是 0x4000。之前备份里 misc 0x4000 挂着一串 `boot-recovery --wipe_all`，但 uboot 根本不读那里，所以机器一直正常开机。写 BCB 要写 0x0，并且顺手把 0x4000 的残留清掉。

实测写对命令后设备确实能进 recovery，但 recovery 在墨水屏上因为 e-ink 显示初始化崩溃会自动重启，没法停留，所以这条路在真机上没走通。

## 其他杂项

- vbmeta 是 VERIFICATION_DISABLED（flags=0x2），AVB 分区哈希校验是关的，改过的 boot 不会被 AVB 拒。国行锁的只是 fastboot unlock（uboot 报 `FAILgenerate unlock challenge fail`），loader 直写分区不查解锁。
- loader 对 boot/super/vbmeta/cache/backup/metadata/logo 等分区读保护，`rl` 读出来全是 0xCC 填充，只有 misc/uboot/trust/security/waveform 能读。所以设备侧做不了完整备份，可靠的恢复介质就是国行线刷包本身。
- S001345 这个包的 boot ramdisk 里，`persist.sys.usb.config=none`、`ro.adb.secure=1`、`ro.secure=1`、`ro.debuggable=0`。刷完默认 USB 是 MTP 不是 adb，社区教程里「刷完 adb 直接可连」的说法有待验证。
- ⚠️ **boot 重打包的两个硬性要求（SP523FC 2026-08-25 实证，同一块板同样适用）**：
  1. **保留结尾 second/DTB 设备树区段**（ramdisk 后 ~321KB，头部 second_size=0x32000 声明；丢了它内核无设备树，黑屏无响应）
  2. **重算头部 `id` 字段**：uboot 用 SHA1 校验 boot 镜像（`common/image-android.c`，字符串 "Hash from header"/"Hash real"/"ANDROID: Hash OK"），算法 = SHA1(kernel数据+size字段, ramdisk数据+size字段, second数据+size字段, recovery_dtbo+size, dtb+size)，与 id 比对，不匹配拒启。**坑**：`recovery_dtbo_offset` 是 u64，`dtb_size` 在偏移 0x670 而非标准布局的 0x66c。详见 `docs/SP523FC-QiTian/README.md` 的"boot 镜像的完整结构"一节。

---
> **📜 版权声明**
> 本仓库所有内容（包括但不限于代码、文档、脚本）仅供学习参考。
> **未经作者书面授权，禁止任何形式的商用、转载、修改或二次分发。**
> 根据 GitHub Terms of Service，公开仓库允许 fork，但默认版权法保留所有权利。
