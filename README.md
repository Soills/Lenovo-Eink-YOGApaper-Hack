# 联想墨水屏平板

**食用方法**
1. 克隆本项目到本地
2. 设备关机，卡针顶住底部小孔，插 USB 进 **Loader / Maskrom** 模式（设备管理器出现 Rockusb）
3. 双击 `一键流程.cmd` → `[1]` 刷 root boot（`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`，已实测可开机）；`[2]` 刷回原版 / `[3]` 整包刷机救砖
4. 开机插 USB（boot 默认 adb）：`adb install files\magisk_v28.1.apk` 装 Magisk 管理器（提示签名冲突先 `adb uninstall com.topjohnwu.magisk`）
5. Magisk → 模块 → 从本地安装 → `模块\All-in-One.zip` → 重启 → 开发者选项 / 解除安装限制 / adb 全开，桌面出现 SP523FC Helper

**Lenovo E-ink Tablets — Rockchip (RK3566) Reverse-Engineering & Flashing Notes**

两台联想墨水屏平板的逆向和刷机全记录：**YOGA Paper（SP101FU）** 与 **启天 Smart Paper（SP523FC）**。两者是同一块硬件板 **Louvre_3566_4G**（RK3566 / 4GB / 64GB / Android 11 · ZUI）的两个市场版本，但**固件不互通**：boot 携带型号/地区标识（SP523FC=CCN / SP101FU=PRC），系统开机自检比对 + uboot 对 boot 做 SHA1 校验，跨刷必拒启。

**EN:** Full reverse-engineering and flashing records for two Lenovo e-ink tablets — **YOGA Paper (SP101FU)** and **QiTian Smart Paper (SP523FC)**. They share one hardware board (**Louvre_3566_4G**: RK3566, 4GB RAM / 64GB eMMC, Android 11 · ZUI) as two market SKUs, but the firmware is **NOT interchangeable**: the boot image embeds model/region identifiers (SP523FC=CCN / SP101FU=PRC) that the system cross-checks at boot, and uboot SHA1-verifies the boot image — cross-flashing always fails.

仓库内容：源码级逆向的 boot 链全分析（Android boot v2 布局、Rockchip uboot 的 SHA1 boot-id 校验 `common/image-android.c`、**重打包丢 second/DTB 区段必黑屏**）、loader 分区读保护、RK 出厂 UserMode 后门、ZUI 焊死的开发者选项、Magisk root 注入、默认开 adb 的完整解法，以及配套自动化脚本——`build_boot.py` 已把全部逆向结论编码进去，一键重打包 + 重算 id。

**EN:** What's inside: source-level analysis of the full boot chain — Android boot v2 layout, Rockchip uboot's SHA1 boot-id verification (`common/image-android.c`), the post-ramdisk **second/DTB section that bricks every naive repack**, loader partition read protection, the RK factory "UserMode" backdoor, ZUI's welded-shut developer options, Magisk root injection, and enabling adb by default — plus the automation: `build_boot.py` encodes every finding and repacks + recomputes the id in one step.

**SP523FC 已实测 root 成功（2026-08-25），root boot 可开机。** / **SP523FC root verified working (2026-08-25), the root boot image boots.**

---

## 🎯 面向 RK 研究者的核心收获 / TL;DR for Rockchip researchers

> 以下结论**不只适用于这两台联想墨水屏**——它们揭示的是 **Rockchip 安卓设备（RK3566/RK3399/RK3568/RK3588 等）的一整套共性机制**，全部基于固件 / uboot 源码级逆向，并已用原厂镜像精确验证，可直接迁移到其他 RK 设备，或用来理解/修复你自己的重打包工具。

**EN:** These findings are **not limited to these two Lenovo tablets** — they expose mechanisms common to **Rockchip Android devices (RK3566/RK3399/RK3568/RK3588, …)**. Every claim was derived from firmware / uboot source-level reverse engineering and verified against the factory images, so they port directly to other RK hardware and to your own repack tooling.

| 机制 Mechanism | 适用范围 Scope | 关键点 / Key point |
|---|---|---|
| RK boot 镜像结构（header/kernel/ramdisk/second/dtb） | 所有 Android 8+ 的 RK 设备 | ramdisk 偏移 = `(1+ceil(kernel_size/page))*page`；header 页=2048；`id` 在 0x240 |
| **结尾 second/DTB 区段**（RSCE 资源容器 + 2 个 DTB） | 所有带 RSCE 容器的 RK boot | **重打包丢了它 = 黑屏开不了机**，必须整段保留、按页对齐挪位 |
| **uboot SHA1 校验 boot id**（`common/image-android.c`） | 开启 `CONFIG_ANDROID_BOOT_IMAGE_HASH` 的 RK uboot | 改过 boot 必须重算 id（算法见下），否则 `return -EBADFD` 拒启 |
| **`dtb_size` 字段偏移陷阱** | 所有 Android boot v2 头 | `recovery_dtbo_offset` 是 u64 → `dtb_size` 实际在 **0x670**，按标准布局解析会读错 |
| RK loader 分区读保护（读出 0xCC） | 所有 RK loader | boot/super/vbmeta 等只写不读；root 后 `dd` 绕过做备份 |
| **RK 出厂 UserMode 后门** | RK 工程/测试固件 | `su --set-user-mode 2 --passwd rockchip`（mode1=adb，mode2=root） |
| uboot 读 BCB 在偏移 **0x0** | RK uboot（recovery 引导） | 不是 0x4000；0x4000 的 `--wipe_all` 残留会被无视 |
| 消费版 vbmeta = `VERIFICATION_DISABLED` | RK 消费版固件 | flags=0x2，AVB 不拦改过的 boot；只锁了 fastboot unlock |
| 国行 ROM 砍 adb 特性 | 大量国产 ROM | USB HAL 只认充电/MTP + init.rc 缺 adb TCP 触发器（见下） |
| ZUI `isSupportDoubleList` 焊死开发者选项 | 联想 ZUI 全系 | `EinkUtils.isSupportDoubleList()` 硬编码 true，连点版本号被短路 |

> **搜索关键词 / Keywords**：rockchip root / RK3566 root / RK boot 重打包 / rockchip boot repack / RK uboot image hash / ANDROID_BOOT_IMAGE_HASH / boot v2 dtb offset / RSCE resource container / 瑞芯微 刷机 / 墨水屏平板 root / Lenovo YOGA Paper SP101FU / 启天 Smart Paper SP523FC / ZUI isSupportDoubleList

---

## 设备 / Devices

| SKU | 型号 Model | 市场 Market | 固件 Firmware | 状态 Status |
|---|---|---|---|---|
| YOGA Paper | SP101FU | 中国大陆 PRC | S001345（2024-12-16） | 逆向完成，已有第三方项目完成，详见docs |
| 启天 Smart Paper | SP523FC | 中国大陆/教育 CCN | S001014（2023-03-01） | ✅ **root 成功**（2026-08-25） |

硬件 / Hardware：RK3566（四核 Cortex-A55）、4GB RAM / 64GB eMMC、10.3" 墨水屏、Android 11 · ZUI 13。同一块板 `Louvre_3566_4G`，两个市场 SKU，**固件不互通**。 / Same board `Louvre_3566_4G`, two market SKUs, **incompatible firmware**.

---

## 目录 / Repository structure

```
docs/
  SP101FU-YOGA-Paper/     逆向与 adb 路线（中文 README.md + 英文 README.en.md）
  SP523FC-QiTian/         root、开 adb、刷机流程（中文 README.md + 英文 README.en.md）
build_boot.py             核心逆向工具：解析 boot 布局 / cpio 注入 / 保留 second+DTB / 重算 SHA1 id（Python 3，仅标准库）
一键流程.cmd              SP523FC 刷机菜单脚本（GBK 编码，Windows 双击运行）
flash_boot.sh             bash 版刷 boot 脚本（Git Bash 用）
upgrade_tool.exe          瑞芯微官方命令行烧录工具
adb.exe + DLL             自带 adb 环境
img/                      固件镜像
files/                    驱动 / Magisk APK / MiniLoaderAll.bin
模块/All-in-One.zip       整合 Magisk 模块（开发者选项 + adb + 解除安装限制 + 壁纸替换）
paper（壁纸）/            壁纸替换模块
```

---

## 快速开始 / Quick start

1. 设备关机，卡针顶住底部小孔，插 USB 进 **Loader / Maskrom** 模式（设备管理器出现 Rockusb）
2. 双击 `一键流程.cmd` → `[1]` 刷 root boot（`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`，已实测可开机）；`[2]` 刷回原版 / `[3]` 整包刷机救砖
3. 开机插 USB（boot 默认 adb）：`adb install files\magisk_v28.1.apk` 装 Magisk 管理器（提示签名冲突先 `adb uninstall com.topjohnwu.magisk`）
4. Magisk → 模块 → 从本地安装 → `模块\All-in-One.zip` → 重启 → 开发者选项 / 解除安装限制 / adb 全开，桌面出现 SP523FC Helper

**EN:** 1) Power off, push the pin in the bottom pinhole, plug in USB to enter **Loader/Maskrom** (Rockusb appears in Device Manager). 2) Run `一键流程.cmd` → `[1]` to flash the root boot (`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`, verified bootable); `[2]` restore the stock boot / `[3]` full-firmware flash to unbrick. 3) Boot and plug USB (the boot defaults to adb): `adb install files\magisk_v28.1.apk` (uninstall `com.topjohnwu.magisk` first on signature conflict). 4) Install `模块\All-in-One.zip` from Magisk → Modules → Install from storage, reboot — developer options, install restrictions and adb are all unlocked; a "SP523FC Helper" settings app appears.

**手动刷写命令 / Manual flashing (`upgrade_tool`):**
```
upgrade_tool LD                             # 检测设备（Loader / Maskrom / No found）
upgrade_tool PL                             # 查看分区表
upgrade_tool WL 0x14000 boot.img            # 写 boot_a（LBA）
upgrade_tool WL 0x46000 boot.img            # 写 boot_b（LBA）
upgrade_tool DB files/MiniLoaderAll.bin     # Maskrom 模式：先下载 loader 进设备
upgrade_tool RCI                            # 读芯片信息（确认 loader 已起来）
upgrade_tool RD                             # 重启设备
upgrade_tool uf update_nowaveform.img       # 整包刷机（救砖）
```
> Maskrom（无 loader）时必须先 `DB` 下载 `files/MiniLoaderAll.bin`，`RCI` 能读到芯片信息后再 `WL`。

> 备用：若 USB adb 不出（个别机器 USB HAL 只认 MTP），用 MTP 把 `模块/All-in-One.zip` 复制进设备，Magisk 装模块后 adb 由模块强制开启（USB + WiFi `adb connect 设备IP:5555`）。

**完整从零流程**（驱动、adb 授权、应用安装等细节）见 [docs/SP523FC-QiTian/README.md](docs/SP523FC-QiTian/README.md)。

---

## 🔬 逆向专题 / Reverse-engineering deep dives

> 所有结论都有固件/代码依据，出处标注为 `build_boot.py` 或对应文档，可复现。 / Every claim below is grounded in firmware/code with the source cited; everything is reproducible.

### 1. RK boot 镜像完整布局 / Full boot image layout

从官方整包 `update_nowaveform.img`（RKFW 格式）偏移 `0x4df226` 解出真实 boot 分区（65,226,752 字节）。Android boot v2 头，`page=2048`。真实布局（SP523FC S001014）：

```
0x000000 - 0x0007ff   header（page 0，hdr_v=2）
0x000800 - 0x1d7d000  kernel（kernel_size=0x1d7c010，按 2048 页对齐）
0x1d7d000 - 0x3de5a4c  ramdisk（ramdisk_size=0x2068a4c，gzip → cpio 70,404,096 B）
0x3de6000 - 0x3e18000  second 区段（second_size=0x32000=200KB，RSCE 资源容器含 DTB#1）
0x3e18000 - 0x3e34800  DTB#2 区段 + 尾部填充
```

- **ramdisk 偏移 = `(1 + ceil(kernel_size/page)) * page`**，`page=2048`。用 4096 对齐会算错
- 各区段按**相对页对齐**定位（不是绝对偏移）——重打包时把后段整体挪到新 ramdisk 末尾的页对齐位置即可
- 关键 header 字段（`build_boot.py` 解析）：

| 偏移 Offset | 字段 Field | 说明 Note |
|---|---|---|
| 0x008 | `kernel_size` (u32) | 精确数据大小（不对齐） |
| 0x010 | `ramdisk_size` (u32) | 重打包时唯一要改的字段 |
| 0x018 | `second_size` (u32) | 声明 RSCE 资源容器（含 logo、rk-kernel.dtb） |
| 0x024 | `page_size` (u32) | =2048 |
| 0x240 | `id[20]` | uboot SHA1 校验目标（见下） |
| 0x660 | `recovery_dtbo_offset` (u64) | **u64** —— 把 `dtb_size` 顶离标准位置 |
| 0x670 | `dtb_size` (u32) | 实际在 0x670，按标准布局解析会读错 |

**EN:** Extracting the real boot partition (65,226,752 B) from the official RKFW package at offset `0x4df226` gives an Android boot v2 image with `page=2048`. The ramdisk offset is `(1+ceil(kernel_size/page))*page`; all sections are located by *relative page alignment*, not absolute offsets. Header fields as parsed by `build_boot.py` — note `recovery_dtbo_offset` is a **u64** starting at 0x660, which pushes `dtb_size` to **0x670** (a standard-layout parser reads garbage).

### 2. uboot SHA1 校验 boot id / uboot SHA1 boot-id verification

反汇编 uboot + 对照 Rockchip 源码（`common/image-android.c`，字符串 `"Hash from header"` / `"Hash real"` / `"ANDROID: Hash OK"`）确认：**uboot 对 boot 镜像整体做 SHA1，与头部 `id` 字段比对，不匹配直接拒启（`return -EBADFD`）。** 算法（已用原厂 id `7a4eb86d...` 精确验证）：

```
SHA1(
  kernel_data[pgsz : pgsz+kernel_size] + kernel_size(u32 LE)
  + ramdisk_data + ramdisk_size(u32 LE)
  + second_data + second_size(u32 LE)
  + recovery_dtbo_data(0字节) + recovery_dtbo_size(u32 LE)
  + dtb_data + dtb_size(u32 LE)
)
```

- kernel 跳过头部页（`pgsz=2048`）；各数据块取**精确 size 字段值**（不对齐）；size 字段在数据**之后**追加
- 校验失败 uboot 打印三段哈希并 `return -EBADFD` 拒启
- **改了 ramdisk 必须用此算法重算 id 写回 0x240**，否则旧 id 对不上新内容 → 不开机
- `build_boot.py` 的 `compute_boot_id()` 内置该算法，自动处理

**EN:** Disassembly plus the Rockchip source (`common/image-android.c`) confirm uboot SHA1-hashes the whole boot image and compares it against the header `id` field, rejecting with `return -EBADFD` on mismatch. Kernel data starts after the header page; each data block uses the exact size-field value (not page-aligned) and its size is appended *after* the data. Any ramdisk edit requires recomputing the id — `compute_boot_id()` in `build_boot.py` does exactly this.

### 3. 重打包 / Repack rules（两个致命坑，`build_boot.py` 已解决）

1. **必须保留结尾 second/DTB 区段**：原厂 boot 在 ramdisk 后有 ~321KB（`second_size=0x32000` + 2 个 DTB）。之前所有 repack（含旧的 original.img）都把它丢了，而头部仍声明它 → 设备按声明去读全零区 → 内核无设备树 → 显示初始化前挂死 → **黑屏、开机键无反应**。这是所有改版 boot 开不了机的第一层根因，与 Magisk 版本、payload、prop 改动全部无关。
2. **必须重算 id**：保留区段后仍不开机 = uboot SHA1 校验失败（第二层根因），用上面的算法重算。

`build_boot.py` 的正确做法：以完整原厂 boot 为基底 → 只替换 ramdisk（cpio 注入 Magisk，或只改 prop.default）→ 结尾 second+DTB 区段**逐字节保留**并整体挪到新 ramdisk 末尾页对齐处 → 头部只改 `ramdisk_size` → 重算 `id` 写回。gzip 用与出厂一致的头（`FLG=0 MTIME=0 XFL=0 OS=3`）。Magisk payload 取自社区已验证可开机的 SP101FU 包（V3zOF），`.backup/.magisk` 的 SHA1 按本机真 stock 重新生成。

三种模式：

```
python build_boot.py magisk    # → boot_SP523FC_S001014_magisk_root_adbmtp.img（Magisk root + adb）
python build_boot.py noadb     # → boot_SP523FC_S001014_adbmtp_nomagisk.img（只开 adb，诊断用）
python build_boot.py noop      # → boot_SP523FC_S001014_noop.img（内容不变只重压缩，隔离"重压缩是否影响启动"）
```

**EN:** Trap #1 — dropping the post-ramdisk second/DTB section (RSCE container + DTBs, ~321KB declared by `second_size=0x32000`) while the header still declares it: the device reads a zeroed region, the kernel gets no device tree and dies before display init → black screen, no response. This is why *every* naive repack failed — independent of Magisk version, payload or prop changes. Trap #2 — the uboot SHA1 check rejects the modified image. Correct repack (`build_boot.py`): base = full stock boot, replace only the ramdisk, preserve the second/DTB section byte-for-byte shifted to the page-aligned end of the new ramdisk, change only `ramdisk_size`, then recompute `id`. The gzip is emitted with a factory-identical header. Magisk payloads come from a community-proven SP101FU package (V3zOF), with `.backup/.magisk`'s SHA1 regenerated against the true stock image. Modes: `magisk` / `noadb` / `noop` (the last isolates whether recompression alone affects boot).

### 4. ZUI 开发者选项焊死 / Developer options lockout

- 连点版本号没反应：`com.eink.settings.EinkUtils.isSupportDoubleList()` 硬编码 `return true`，而 `BuildNumberPreferenceController.handlePreferenceTreeClick()` 第一行就是 `if (isSupportDoubleList() || ...) return false;` —— 连点逻辑被代码短路，点多少次都不会动
- 搜索不到：开发者选项页的搜索索引被 `DevelopmentSettingsEnabler.isDevelopmentSettingsEnabled()` 挡住
- Activity 在 manifest 里 `android:enabled="false"`，另有 `DevelopmentSettingsDisabledActivity` 占位，`am start` 也打不开
- **Android 11 system-as-root 下 boot 无法改 Settings 数据库**：recovery-in-boot 的 ramdisk 没有根级 `init.rc`，正常启动只加载 system 分区里的 `/system/etc/init/*.rc`；放 ramdisk 的 `system/etc/init/zz_adb.rc` 会被挂载的 system 覆盖，recovery 专用 rc（`init.recovery.rk30board.rc`）正常启动根本不加载
- → 唯一可行路线：**root（Magisk）→ 刷模块 → 开机以 root 解锁**。模块实际执行（等效手动命令）：

```
pm enable 'com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity'
settings put global development_settings_enabled 1
```

**EN:** ZUI's settings app hardcodes `isSupportDoubleList()=true`, which short-circuits the build-number tap (the first line of `handlePreferenceTreeClick()` returns false), hides the entry from search, and the Activity is `enabled="false"` in the manifest. Because this is Android 11 system-as-root with recovery-in-boot, the boot ramdisk cannot touch the Settings DB: no root-level `init.rc` is loaded in normal boot, anything under ramdisk `system/` is shadowed by the mounted system partition, and the recovery-only rc file is never loaded. The only working path is root via Magisk, then a module that runs `pm enable` + `settings put` at boot.

### 5. adb / USB 链路 / adb & USB

- 国行 USB HAL **只认充电/MTP**：`persist.sys.usb.config=adb` 不生效 → USB adb 从物理层面不可用
- 系统 init.rc **缺 `on property:persist.adb.tcp.port=* → start adbd` 触发器**：光设端口不会拉起 adbd
- boot 层解法（prop.default）：`persist.sys.usb.config=adb` + **`sys.usb.config=adb`**（首阶段启动即拉起 adbd + adb gadget，绕开框架层的 MTP 偏好）+ `persist.adb.tcp.port=5555`（兜底）。**注意**：persist 属性存在 /data/property，改过要清一次 /data，否则旧的 `none` 会赢
- 兜底：All-in-One 模块开机以 root 强制 setprop；WiFi adb `adb connect 设备IP:5555`

**EN:** The CN ROM's USB HAL only honors charging/MTP, and the system init.rc lacks the `on property:persist.adb.tcp.port=* → start adbd` trigger, so USB adb is physically unavailable and setting the port alone never starts adbd. The boot-level fix lives in `prop.default`: set `sys.usb.config=adb` (starts adbd + the adb gadget at first-stage boot, bypassing the framework's MTP preference) plus `persist.sys.usb.config=adb` and `persist.adb.tcp.port=5555`. Caveat: persisted properties live in /data/property — clear /data once or the old `none` wins. Fallback: the All-in-One module force-enables adb (USB + WiFi `adb connect <ip>:5555`) at boot as root.

### 6. recovery-in-boot、BCB、vbmeta、分区读保护 / Recovery, BCB, vbmeta, partitions

- **recovery-in-boot**：boot ramdisk 自带标准 AOSP recovery，其 adbd 是 root。进 recovery 后 `adb shell` → `setprop persist.sys.usb.config adb` → `reboot`，属性写进 /data/property 跨重启存活。SP101FU 实测 recovery 在墨水屏上因 e-ink 显示初始化崩溃会自动重启，真机没走通，但原理成立
- **BCB 位置**：uboot 读 **0x0** 处的 BCB（AOSP 标准位置），**不是** 0x4000。之前备份里 0x4000 挂着 `boot-recovery --wipe_all` 残留，uboot 根本不读 → 机器一直正常开机
- **vbmeta = VERIFICATION_DISABLED**（flags=0x2）：AVB 分区哈希校验关闭，改过的 boot 不会被 AVB 拒；国行只锁了 fastboot unlock（uboot 报 `FAILgenerate unlock challenge fail`），loader 直写分区不查解锁
- **loader 读保护**：`rl` 读 boot/super/vbmeta/cache/backup/metadata/logo 全返回 0xCC；只有 misc/uboot/trust/security/waveform 可读 → 设备侧做不了完整备份。**root 后直接 `dd` 绕过**：
  ```
  adb shell su -c 'dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4096'
  ```

**EN:** Recovery-in-boot: the boot ramdisk carries AOSP recovery whose adbd is root — from recovery you can `setprop persist.sys.usb.config adb`, which survives reboot via /data/property. uboot reads the BCB at offset **0x0**, not 0x4000 (a leftover `--wipe_all` at 0x4000 was simply ignored). vbmeta is `VERIFICATION_DISABLED` (flags=0x2), so AVB never rejects a modified boot — only fastboot unlock is blocked. The loader read-protects boot/super/vbmeta/cache/backup/metadata/logo (reads back 0xCC); only misc/uboot/trust/security/waveform are readable, so full backups aren't possible from the device side — root makes them trivial with `dd`.

### 7. RK 出厂 UserMode 后门 / RK factory "UserMode" backdoor

出厂测试应用 `DeviceTest.apk` 引用 RK 售后通道：`su --set-user-mode <n> --passwd rockchip`（mode1=开 adb，mode2=超级用户/root），默认口令 `rockchip`。**但消费版固件里没有 su 二进制**，这条通道在本机走不通；折腾 RK 工程固件/测试固件时可以留意。

**EN:** The factory test app `DeviceTest.apk` references RK's service-channel: `su --set-user-mode <n> --passwd rockchip` (mode1 = enable adb, mode2 = superuser), default password `rockchip`. Consumer firmware ships no `su` binary so it's a dead end here — but worth probing on RK engineering/test firmware.

---

## 工具 / Tooling

| 工具 Tool | 说明 Description |
|---|---|
| `build_boot.py` | 核心逆向工具：解析 boot 布局、cpio 注入 Magisk、保留 second/DTB 区段、重算 SHA1 id（Python 3，仅标准库，无第三方依赖） |
| `一键流程.cmd` | SP523FC 刷机菜单：刷 root boot / 回原版 / 整包救砖 / 说明（GBK 编码，Windows 双击运行） |
| `flash_boot.sh` | 等价 bash 版（Git Bash），带设备等待循环（最长 ~10 分钟）和日志 |
| `upgrade_tool.exe` | 瑞芯微官方命令行烧录工具（LD / PL / WL / RD / DB / RCI / uf） |
| `adb.exe` + DLL | 自带 adb 环境 |

LBA 分区表（SP523FC）：`boot_a=0x14000`、`boot_b=0x46000`、`super=0x200800`。这台 loader 不支持 LP 逻辑分区写入（分区表里只有物理 super 没有 system），所以改 system 只能整块写 super 分区（`WL 0x200800 super_modified.sparse`）。

---

## 说明 / Notes

- 仓库不含固件镜像和第三方工具二进制（见 `.gitignore`），只有文档、脚本和逆向结论
- 刷机有风险，数据会清空，砖了自己负责
- ⚠️ **重打包 boot 必须保留结尾 second/DTB 区段** + **重算 id**（详见"逆向专题"）
- 固件与设备不匹配会开机自检失败，boot 必须和系统同版本配套
- 文档：中文 `docs/*/README.md`，英文 `docs/*/README.en.md`

---

> **📜 版权声明 / Copyright**
> 本仓库所有内容（包括但不限于代码、文档、脚本）仅供学习参考。
> **未经作者书面授权，禁止任何形式的商用、转载、修改或二次分发。**
> 根据 GitHub Terms of Service，公开仓库允许 fork，但默认版权法保留所有权利。
> All content in this repository (code, docs, scripts) is for learning and reference only. No commercial use, redistribution, modification or secondary distribution without the author's written permission. Per GitHub Terms of Service, public repos may be forked, but default copyright law reserves all rights.
