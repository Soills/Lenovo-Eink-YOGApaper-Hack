# 联想墨水屏平板（Rockchip RK3566）逆向与刷机笔记

> 🌏 语言 / Language：**中文** ｜ [**English**](README.en.md)

**快速食用方法**

1. 克隆本项目到本地
2. 设备关机，卡针顶住底部小孔，插 USB 进 **Loader / Maskrom** 模式（设备管理器出现 Rockusb）
3. 双击 `一键流程.cmd` → `[1]` 刷 root boot（`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`，已实测可开机）；`[2]` 刷回原版 / `[3]` 整包刷机救砖
4. 开机插 USB（boot 默认 adb）：`adb install files\magisk_v28.1.apk` 装 Magisk 管理器（提示重启后再安装一次Magisk 管理器）
5. Magisk → 模块 → 从本地安装 → `模块\All-in-One.zip` → 重启 → 开发者选项 / 解除安装限制 / adb 全开

---

两台联想墨水屏平板的逆向和刷机全记录：**YOGA Paper（SP101FU）** 与 **启天 Smart Paper（SP523FC）**。两者是同一块硬件板 **Louvre_3566_4G**（RK3566 / 4GB / 64GB / Android 11 · ZUI）的两个市场版本，但**固件不互通**：boot 携带型号/地区标识（SP523FC=CCN / SP101FU=PRC），系统开机自检比对 + uboot 对 boot 做 SHA1 校验，跨刷必拒启。

仓库内容：源码级逆向的 boot 链全分析（Android boot v2 布局、Rockchip uboot 的 SHA1 boot-id 校验 `common/image-android.c`、**重打包丢 second/DTB 区段必黑屏**）、loader 分区读保护、RK 出厂 UserMode 后门、ZUI 焊死的开发者选项、Magisk root 注入、默认开 adb 的完整解法，以及配套自动化脚本——`build_boot.py` 已把全部逆向结论编码进去，一键重打包 + 重算 id。

**SP523FC 已实测 root 成功（2026-08-25），root boot 可开机。**

---

##  面向 RK 研究

> 以下结论**不只适用于这两台联想墨水屏**——它们揭示的是 **Rockchip 安卓设备（RK3566/RK3399/RK3568/RK3588 等）的一整套共性机制**，全部基于固件 / uboot 源码级逆向，并已用原厂镜像精确验证，可直接迁移到其他 RK 设备，或用来理解/修复你自己的重打包工具。

| 机制 | 适用范围 | 关键点 |
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
| ZUI `isSupportDoubleList` 开发者选项 | 联想 ZUI 全系 | `EinkUtils.isSupportDoubleList()` 硬编码 true，连点版本号无效|

> **搜索关键词**：rockchip root / RK3566 root / RK boot 重打包 / rockchip boot repack / RK uboot image hash / ANDROID_BOOT_IMAGE_HASH / boot v2 dtb offset / RSCE resource container / 瑞芯微 刷机 / 墨水屏平板 root / Lenovo YOGA Paper SP101FU / 启天 Smart Paper SP523FC / ZUI isSupportDoubleList

---

## 设备

| SKU | 型号 | 市场 | 固件 | 状态 |
|---|---|---|---|---|
| YOGA Paper | SP101FU | 中国大陆 PRC | S001345（2024-12-16） | 逆向完成，已有第三方项目完成，详见 docs |
| 启天 Smart Paper | SP523FC | 中国大陆/教育 CCN | S001014（2023-03-01） | **root 成功**（2026-08-25） |

硬件：RK3566（四核 Cortex-A55）、4GB RAM / 64GB eMMC、10.3" 墨水屏、Android 11 · ZUI 13。同一块板 `Louvre_3566_4G`，两个市场 SKU。

---

## 目录结构

```
docs/
  SP101FU-YOGA-Paper/     逆向与 adb 路线（中文 README.md + 英文 README.en.md）
  SP523FC-QiTian/         root、开 adb、刷机流程（中文 README.md + 英文 README.en.md）
    ui-dumps/             真机 UI 层级转储（uiautomator：设置页/状态栏/桌面/拦截对话框）
build_boot.py             核心逆向工具：解析 boot 布局 / cpio 注入 / 保留 second+DTB / 重算 SHA1 id（Python 3，仅标准库）
一键流程.cmd              SP523FC 刷机菜单脚本（GBK 编码，Windows 双击运行）
flash_boot.sh             bash 版刷 boot 脚本（Git Bash 用）
upgrade_tool.exe          瑞芯微官方命令行烧录工具
adb.exe + DLL             自带 adb 环境
img/                      固件镜像 → 在 [Release boot-images-v1](https://github.com/Soills/Lenovo-Eink-YOGApaper-Hack/releases/tag/boot-images-v1)（GitHub 单文件限 100MB，走 Release 附件）
files/                    驱动 / Magisk APK / MiniLoaderAll.bin（不入库）
模块/All-in-One.zip       整合模块 v2.3（开发者选项/adb/解除安装限制/PackageInstaller 解锁/显示档位/壁纸档位 + Helper App + Amaze 文件管理器；源码在 模块/HelperApp/）
_pi/                      PackageInstaller 解锁工具链：pi.apk（原版安装器）+ 解锁 APK/模块/补丁脚本 + 反编译源码（详见 _pi/README.md）
```

---

## 快速开始

1. 设备关机，卡针顶住底部小孔，插 USB 进 **Loader / Maskrom** 模式（设备管理器出现 Rockusb）
2. 双击 `一键流程.cmd` → `[1]` 刷 root boot（`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`，已实测可开机）；`[2]` 刷回原版 / `[3]` 整包刷机救砖
3. 开机插 USB（boot 默认 adb）：`adb install files\magisk_v28.1.apk` 装 Magisk 管理器（提示签名冲突先 `adb uninstall com.topjohnwu.magisk`）
4. Magisk → 模块 → 从本地安装 → `模块\All-in-One.zip` → 重启 → 开发者选项 / 解除安装限制 / adb / 显示档位 / 壁纸档位全开，桌面出现 SP523FC Helper（可开关各档位，含「打开开发者选项」「root 安装 APK」入口）

**手动刷写命令（`upgrade_tool`）**：

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

## 🔬 逆向专题

> 所有结论都有固件/代码依据，出处标注为 `build_boot.py` 或对应文档，可复现。

### 1. RK boot 镜像完整布局

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

| 偏移 | 字段 | 说明 |
|---|---|---|
| 0x008 | `kernel_size` (u32) | 精确数据大小（不对齐） |
| 0x010 | `ramdisk_size` (u32) | 重打包时唯一要改的字段 |
| 0x018 | `second_size` (u32) | 声明 RSCE 资源容器（含 logo、rk-kernel.dtb） |
| 0x024 | `page_size` (u32) | =2048 |
| 0x240 | `id[20]` | uboot SHA1 校验目标（见下） |
| 0x660 | `recovery_dtbo_offset` (u64) | **u64** —— 把 `dtb_size` 顶离标准位置 |
| 0x670 | `dtb_size` (u32) | 实际在 0x670，按标准布局解析会读错 |

### 2. uboot SHA1 校验 boot id

反汇编 uboot + 对照 Rockchip 源码（`common/image-android.c`，字符串 `"Hash from header"` / `"Hash real"` / `"ANDROID: Hash OK"`）确认：**uboot 对 boot 镜像整体做 SHA1，与头部 `id` 字段比对，不匹配直接拒启（`return -EBADFD`）。** 算法（已用原厂 id `7a4eb86d...` 验证）：

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
- `build_boot.py` 的 `compute_boot_id()` 内置该算法

### 3. 重打包

1. **必须保留结尾 second/DTB 区段**：原厂 boot 在 ramdisk 后有 ~321KB（`second_size=0x32000` + 2 个 DTB）。之前所有 repack（含旧的 original.img）都把它丢了，而头部仍声明它 → 设备按声明去读全零区 → 内核无设备树 → 显示初始化前挂死 → **黑屏、开机键无反应**。这是所有改版 boot 开不了机的第一层根因，与 Magisk 版本、payload、prop 改动全部无关。
2. **必须重算 id**：保留区段后仍不开机 = uboot SHA1 校验失败（第二层根因），用上面的算法重算。

`build_boot.py` 的正确做法：以完整原厂 boot 为基底 → 只替换 ramdisk（cpio 注入 Magisk，或只改 prop.default）→ 结尾 second+DTB 区段**逐字节保留**并整体挪到新 ramdisk 末尾页对齐处 → 头部只改 `ramdisk_size` → 重算 `id` 写回。gzip 用与出厂一致的头（`FLG=0 MTIME=0 XFL=0 OS=3`）。Magisk payload 取自社区已验证可开机的 SP101FU 包（V3zOF），`.backup/.magisk` 的 SHA1 按本机真 stock 重新生成。



### 4. ZUI 开发者选项焊死

- 连点版本号没反应：`com.eink.settings.EinkUtils.isSupportDoubleList()` 硬编码 `return true`，而 `BuildNumberPreferenceController.handlePreferenceTreeClick()` 第一行就是 `if (isSupportDoubleList() || ...) return false;` —— 连点逻辑被代码短路
- 搜索不到：开发者选项页的搜索索引被 `DevelopmentSettingsEnabler.isDevelopmentSettingsEnabled()` 挡住
- Activity 在 manifest 里 `android:enabled="false"`，另有 `DevelopmentSettingsDisabledActivity` 占位，`am start` 也打不开
- **Android 11 system-as-root 下 boot 无法改 Settings 数据库**：recovery-in-boot 的 ramdisk 没有根级 `init.rc`，正常启动只加载 system 分区里的 `/system/etc/init/*.rc`；放 ramdisk 的 `system/etc/init/zz_adb.rc` 会被挂载的 system 覆盖，recovery 专用 rc（`init.recovery.rk30board.rc`）正常启动根本不加载
- → 唯一可行路线：**root（Magisk）→ 刷模块 → 开机以 root 解锁**。模块实际执行：

```
pm enable 'com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity'
settings put global development_settings_enabled 1
```

原厂 Settings 里 `isSupportDoubleList()` **返回 false**，开发者选项 Activity 也没被禁用——和 SP101FU（S001345）不一样。因此 SP523FC **不需要改 Settings APK**，只需设置 `development_settings_enabled=1`（模块已做）。详见 [docs/SP523FC-QiTian/README.md](docs/SP523FC-QiTian/README.md)。

### 5. adb / USB 链路

- 国行 USB HAL **只认充电/MTP**：`persist.sys.usb.config=adb` 不生效
- 系统 init.rc **缺 `on property:persist.adb.tcp.port=* → start adbd` 触发器**：光设端口不会拉起 adbd
- All-in-One 模块开机以 root 强制 setprop；WiFi adb `adb connect 设备IP:5555`

### 6. recovery-in-boot、BCB、vbmeta、分区读保护

- **recovery-in-boot**：boot ramdisk 自带标准 AOSP recovery，其 adbd 是 root。进 recovery 后 `adb shell` → `setprop persist.sys.usb.config adb` → `reboot`，属性写进 /data/property 跨重启存活。SP101FU 实测 recovery 在墨水屏上因 e-ink 显示初始化崩溃会自动重启，真机没走通，但原理成立
- **BCB 位置**：uboot 读 **0x0** 处的 BCB（AOSP 标准位置），**不是** 0x4000。之前备份里 0x4000 挂着 `boot-recovery --wipe_all` 残留，uboot 根本不读 → 机器一直正常开机
- **vbmeta = VERIFICATION_DISABLED**（flags=0x2）：AVB 分区哈希校验关闭，改过的 boot 不会被 AVB 拒；国行只锁了 fastboot unlock（uboot 报 `FAILgenerate unlock challenge fail`），loader 直写分区不查解锁
- **loader 读保护**：`rl` 读 boot/super/vbmeta/cache/backup/metadata/logo 全返回 0xCC；只有 misc/uboot/trust/security/waveform 可读 → 设备侧做不了完整备份。**root 后直接 `dd` 绕过**：

  ```
  adb shell su -c 'dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4096'
  ```

### 7. RK 出厂 UserMode 后门

出厂测试应用 `DeviceTest.apk` 引用 RK 售后通道：`su --set-user-mode <n> --passwd rockchip`（mode1=开 adb，mode2=超级用户/root），默认口令 `rockchip`。**但消费版固件里没有 su 二进制**，这条通道在本机走不通；折腾 RK 工程固件/测试固件时可以留意。
工程机也许可以直接开adb和root

---

## 工具

| 工具 | 说明 |
|---|---|
| `build_boot.py` | 核心逆向工具：解析 boot 布局、cpio 注入 Magisk、保留 second/DTB 区段、重算 SHA1 id |
| `一键流程.cmd` | SP523FC 刷机菜单：刷 root boot / 回原版 / 整包救砖 / 说明（GBK 编码，Windows 双击运行） |
| `flash_boot.sh` | 等价 bash 版（Git Bash），带设备等待循环（最长 ~10 分钟）和日志 |
| `upgrade_tool.exe` | 瑞芯微官方命令行烧录工具（LD / PL / WL / RD / DB / RCI / uf） |
| `adb.exe` + DLL | 自带 adb 环境 |

LBA 分区表（SP523FC）：`boot_a=0x14000`、`boot_b=0x46000`、`super=0x200800`。这台 loader 不支持 LP 逻辑分区写入（分区表里只有物理 super 没有 system），所以改 system 只能整块写 super 分区（`WL 0x200800 super_modified.sparse`）。

---

## 说明

- 仓库不含固件镜像和第三方工具二进制（见 `.gitignore`），只有文档、脚本和逆向结论
- 刷机有风险，数据会清空，砖了自己负责
-  **重打包 boot 必须保留结尾 second/DTB 区段** + **重算 id**（详见"逆向专题"）
- 固件与设备不匹配会开机自检失败，boot 必须和系统同版本配套
- 文档：中文 `docs/*/README.md`，英文 `docs/*/README.en.md`

---

> **📜 版权声明**
> 本仓库所有内容（包括但不限于代码、文档、脚本）仅供学习参考。
> **未经作者书面授权，禁止任何形式的商用、转载、修改或二次分发。**
> 根据 GitHub Terms of Service，公开仓库允许 fork，但默认版权法保留所有权利。
