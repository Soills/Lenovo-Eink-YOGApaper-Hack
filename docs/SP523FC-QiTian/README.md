# 启天 Smart Paper（SP523FC）折腾记录

联想启天 Smart Paper 墨水屏平板，固件自报型号 Lenovo SP523FC（板号 Louvre_3566_4G，和上面的 YOGA Paper SP101FU 是同一块硬件板，只是市场 SKU 和固件版本不同）。出厂固件 S001014（2023-03），系统也是 Android 11 · ZUI。这篇是给这台机器打 root、开 adb、解锁设置的完整记录。

## ✅ 最终结果（2026-08-25）

**root boot 刷入成功，设备正常启动。** 完整链路：`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`（Magisk root + USB=adb + second/DTB 区段 + **重算过的正确 id**）刷入即开机。

之前所有 boot 开不了的**真正原因**是两层叠加：
1. **丢结尾 second/DTB 区段** → 内核无设备树 → 黑屏无响应（见下"boot 镜像的完整结构"）
2. **保留区段后仍不开机** → uboot SHA1 哈希校验失败 → 必须用破解的算法重算 id 写入头部（见下"第二层根因"）

这两个问题都已在 build_boot.py 解决。刷入后下一步：
1. `adb install files\magisk_v28.1.apk` 装 Magisk 管理器（若提示签名冲突，先 `adb uninstall com.topjohnwu.magisk` 再装）
2. Magisk → 模块 → 从本地安装 → `模块\All-in-One.zip`，重启后开发者选项/安装限制/adb 全部自动解锁（含设置界面 App）

## 出厂固件和另一个包的关系

折腾过程中发现两个包不能混用：

- `SP523FC_USR_S001014_2303011705_RK3566_CN` —— 本机出厂固件，型号标识 SP523FC，地区 CCN
- `SP101FU_USR_S001345_241216` —— YOGA Paper 的包，型号标识 SP101FU，地区 PRC

两个包的系统基本上同一套代码，差别在型号/版本/地区标识。boot 必须和系统配套，把 SP101FU 的 boot 刷到 SP523FC 的机器上，开机自检会报「当前系统版本与硬件不匹配」直接拒启；刷回配套 boot 就正常。所以给这台机器做的一切修改，都是基于 SP523FC S001014 这个包。

## boot 镜像的完整结构（2026-08-25 修正，这是所有刷机失败的关键）

从 `update_nowaveform.img`（RKFW 格式）偏移 `0x4df226` 处解出真正的 boot 分区（65,226,752 字节）。Android boot v2 头，page=2048。完整结构：

```
0x000000 - 0x0007ff   header（page 0，hdr_v=2）
0x000800 - 0x1d7d000  kernel（kernel_size=0x1d7c010，按 2048 页对齐到 0x1d7d000）
0x1d7d000 - 0x3de5a4c  ramdisk（stock ramdisk_size=0x2068a4c，gzip → 70,404,096 字节 cpio）
0x3de6000 - 0x3e18000  second 区段（second_size=0x32000 = 200KB，内含 DTB#1，0x1c56f 字节）
0x3e18000 - 0x3e34800  DTB#2 区段（0x1c56f 字节）+ 尾部填充
```

**ramdisk 偏移就是按 header 字段页对齐算出来的 0x1d7d000**（`(1 + ceil(kernel_size/page)) * page`），不存在"比字段早 0x800"的说法——之前算错是用了 4096 对齐。

**关键：boot 镜像自带设备树，结尾的 second+DTB 区段（共 321,536 字节）是启动必需的。**

⚠️ **根因（2026-08-25 确认）：之前所有 repack（包括旧的 original.img 和全部改过的 boot）都只保留了 `头部+内核+ramdisk`，把结尾的 second+DTB 区段整个丢了**，而头部 `second_size=0x32000` 依然声明着它。设备按声明去读 second/设备树 → 读到全零 → 内核没有设备树 → 显示初始化前就挂死 → **黑屏、开机键无反应**。

这解释了为什么**所有**改过的 boot 都启动失败而原厂能开——跟 Magisk 版本、payload、prop 改动全无关。排查时用 `upgrade_tool` 日志（`C:\Users\<user>\upgrade_tool\log\`）对照：14:23 整包刷机成功（真 stock，含区段）能开，14:56 刷的改版 boot（丢区段）就不开。

### 第二层根因：uboot 的 SHA1 哈希校验（保留区段后仍不开机的元凶）

保留了 second/DTB 区段后设备能闪屏（内核+显示起来了）但仍不开机。反汇编 uboot + 对照 Rockchip 源码（`common/image-android.c`，字符串 "Hash from header"/"Hash real"/"ANDROID: Hash OK"）确认：

**uboot 对 boot 镜像做 SHA1 校验，和头部 `id` 字段比对，不匹配直接拒启（`return -EBADFD`）。** 算法（已用原厂 id=7a4eb86d... 验证精确匹配）：

```
SHA1(
  kernel_data[pgsz : pgsz+kernel_size] + kernel_size(u32 LE)
  + ramdisk_data + ramdisk_size(u32 LE)
  + second_data + second_size(u32 LE)
  + recovery_dtbo_data(0字节) + recovery_dtbo_size(u32 LE)
  + dtb_data + dtb_size(u32 LE)
)
```

- kernel 跳过头部页；各数据块取**精确 size 字段值**（不对齐）；size 字段在数据**之后**追加
- **坑**：`recovery_dtbo_offset` 是 u64（8字节），导致 `dtb_size` 在偏移 **0x670**（=0x1C56F，DTB 真实大小），不是标准布局的 0x66c
- 改了 ramdisk 必须**用此算法重算 id 写入头部**，否则校验失败（旧 id 匹配不上新内容）

build_boot.py 已内置 `compute_boot_id()`，重打包自动算好写进 id 字段。

**正确重打包（build_boot.py 已实现）**：
- 以原厂完整 boot 为基底（`img/boot_SP523FC_S001014_original.img`，即完整原厂 boot；从 update 镜像 0x4df226 提取）
- 只替换 ramdisk，kernel 原样
- **结尾的 second+DTB 区段（0x3de6000 起 321,536 字节）原样保留**，整体挪到新 ramdisk 末尾的页对齐位置（设备按相对页对齐定位区段，不是绝对偏移）
- 头部只改 ramdisk_size，其余字段（含 second_size）不动
- 已验证：区段字节与真 stock 逐一相同、DTB 魔数在、内核与原版逐字节一致

> 旧的 original.img（64,906,240 字节）也是丢区段的残缺版，已替换成完整原厂 boot（65,226,752 字节）。一键流程 `[2]` 现在刷回去是安全的。

## 注入 Magisk root

用 Magisk v28.1 的 x86_64 magiskboot（在 VM 上直接跑），对解出来的 ramdisk 做 cpio 注入：

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

注意 payload 必须用 arm64 版（lib/arm64-v8a 下那几个 .so 改名），不能把 x86_64 的 magiskboot 顺手当 magiskinit 塞进去，否则设备上跑不起来。注入完 gzip 回去，按上面的布局组装 boot。

> **payload 选择（2026-08-25）**：自己从 magisk-v28.1.apk 提的 payload（magiskinit 187,808 字节那套）是在设备已经开不了机的时候做的，**从未在真机上验证过**。现在 build_boot.py 改用 SP101FU 社区包（`boot_SP101FU_USR_S001345_241216_magisk_patched-28102_V3zOF.img`）里那套**验证过能开机**的 payload（magiskinit 196,888 + magisk.xz 130,000 + stub 26,276 + init-ld 1,540，同属 28.1 系）。.backup/.magisk 的 SHA1 按本机真 stock 重新生成。

## 默认 adb / 开发者模式（2026-08-25 修正）

这台机器的 ZUI 设置和 SP101FU 一样，开发者选项被 isSupportDoubleList 焊死。boot 层能做的其实**只有改 prop.default**：

- `prop.default` 里 `persist.sys.usb.config=adb`（开机即 adb；本机 USB HAL 只认充电/MTP，USB adb 由 prop.default 强制，MTP 传文件在需要时从 USB 选择器切回）

**⚠️ 修正（2026-08-25 代码检查确认）：之前以为「init.recovery.rk30board.rc 里加 devmode 服务 + zz_adb.rc 就能自动解锁开发者选项」是错的。**

- 这台机器是 recovery-in-boot，ramdisk 里没有根级 `init.rc`，正常启动的 init 只加载**装载后的 system 分区**里的 `/system/etc/init/*.rc`。
- `init.recovery.rk30board.rc` 是 **recovery 专用** rc，正常启动根本不加载 → 写在里面的 devmode 服务（`pm enable` + `settings put development_settings_enabled 1`）**从来没跑过**。
- 放 ramdisk `system/etc/init/zz_adb.rc` 也没用：system 挂载后 ramdisk 的 `system/` 被覆盖，文件不会加载。
- 也就是说：**Android 11 system-as-root 下，boot 镜像无法在正常启动时改 Settings 数据库 → 开发者选项入口无法从 boot 层解锁**。之前 boot 里唯一真正生效的改动就是 prop.default 那行 USB 配置。

**可行路线：root（Magisk）→ 刷 All-in-One 模块 → 开机自动解锁开发者选项/解除安装限制/adb。**

解锁由 `模块\All-in-One.zip`（v2.0）的 service.sh 开机以 root 执行（等效 setup_devmode 的命令，但不用手动跑）：

```
pm enable 'com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity'
settings put global development_settings_enabled 1
```

> **真机修正（2026-08-25 实测）：开发者选项入口在 ZUI 设置里是彻底隐藏的**——连点版本号 8 次毫无反应（`isSupportDoubleList()` 硬编码短路 `handlePreferenceTreeClick`），且 `android.settings.APPLICATION_DEVELOPMENT_SETTINGS` intent 当前解析到 `DevelopmentSettingsDisabledActivity` 占位页。设置 flag 后入口也不会出现在列表里。**可行路径：模块开机 `pm enable` 启用真 Activity 后，用 Helper App 的「打开开发者选项」按钮（发同一个 intent）直达。**

该模块 v2.0 还顺带：`settings put global adb_enabled 1` + `persist.sys.usb.config=adb`（USB adb）、解除安装限制（未知来源 + 全应用 `REQUEST_INSTALL_PACKAGES` 授权）、显示档位（亮度 10 级/深色反色/字体）、壁纸档位（001-005 深浅档）。设置 App（SP523FC Helper）可开关各功能档位，另有「打开开发者选项」「root 安装 APK」快捷入口。

> 旧 boot（`magisk_adb_fixed`）里那些 devmode/zz_adb.rc 是无效改动，已去掉；setup_devmode.cmd 已删除，被 All-in-One 模块取代。


### 关于"解锁所有设置"（2026-08-25 复核）

**重要修正**：SP523FC（S001014）原厂 Settings（`/system/priv-app/TC421_Settings/TC421_Settings.apk`）里 **`EinkUtils.isSupportDoubleList()` 本来就是返回 false**（`const/4 v0, #0`），manifest 里开发者选项 Activity **没有 `android:enabled="false"`**（默认启用）——和 SP101FU（S001345，硬编码 true + enabled=false）**不一样**。

结论：
- **不需要改 Settings APK**（之前那次"改签名 Settings"在原厂上本来就是无效操作，VM 上的 settings.apk 与系统镜像逐字节相同）
- "设置项隐藏"在这台机器上的真实原因 = 开发者选项入口标志 `development_settings_enabled` 未设置
- 模块 service.sh 已做：`settings put global/secure development_settings_enabled 1` + `pm enable` 开发者选项 Activity → 设置主列表即出现"开发者选项"，进入后所有选项可见

## 解锁整个设置 UI

isSupportDoubleList 还把 App 信息、蓝牙、锁屏等一大堆设置项锁了，光靠 boot 层解不开，得改 Settings 应用本身。做法：反编译 TC421_Settings.apk，把 `EinkUtils.isSupportDoubleList()` 的 smali 从 `const/4 v0, 0x1` 改成 `const/4 v0, 0x0`（dex 里就 2 个字节），manifest 里把开发者选项 Activity 的 `enabled="false"` 改成 `true`，重新签名，替换进 system_a 分区。

签名用测试密钥重签就行：这个系统 privapp 权限白名单里 com.android.settings 没有 signer 限制（`privapp-permissions-eink.xml`、`privapp-permissions-platform.xml` 里都没写 `<signer>`），所以新签名也能拿到特权权限。代价是包签名变了，PM 会跟 /data/system/packages.xml 里记录的原签名比对，不一致就忽略新 APK。解决：刷完系统后清一次 userdata（loader 的 EF 命令），让 PM 重新扫描。

改好的 system 在整个 super 里。这台机器的 loader 不支持 LP 逻辑分区写入（`DI -s` 报 "No found system in the parameter"，分区表里只有物理 super 没有 system），所以只能整块写 super 分区：`WL 0x200800 super_modified.sparse`（工具支持 sparse，3.5GB，写满大概十几分钟）。

> **实测结果（2026-08-25）：这个方案走不通，已放弃。** 改签名后的 Settings 刷进去，设备一直无法启动（原因没完全定位，怀疑是 Settings 换了签名后跟系统其它部分的校验对不上，或者 APK 重建+重签本身有问题）。清了 userdata 也不行。所以「解锁整个设置 UI」目前没有可行方案，只能做到 boot 层：开发者选项入口（devmode 服务）+ adb 手动开。上面这段保留下来是备忘，别再照着做了。

## 刷机流程

`一键流程.cmd`（仓库根目录） 是总控菜单：

- `[1]` 刷 root boot（`img/boot_SP523FC_S001014_magisk_root_adbmtp.img`：Magisk root + USB=adb + second/DTB 区段 + 正确 id）—— **已实测可开机**，推荐先刷这个也行
- `[2]` 刷回官方原版 boot（`img/boot_SP523FC_S001014_original.img`，已换成**完整原厂 boot**，含区段）
- `[3]` 整包刷机（官方原包，防砖）
- `[4]` 说明

关键文件（`img/`、`files/`、`模块/` 目录）：

| 文件 | 内容 | 说明 |
|---|---|---|
| `img/boot_SP523FC_S001014_magisk_root_adbmtp.img` | Magisk root + second/DTB 区段 + 正确 id | **主用，实测可开机** |
| `img/boot_SP523FC_S001014_original.img` | 完整原厂 boot（65,226,752 字节） | 刷回原版/恢复 |
| `files/magisk_v28.1.apk` | Magisk 28.1 管理器 | 直接安装 |
| `files/MiniLoaderAll.bin` | Maskrom 模式恢复 loader | 救砖 |
| `files/DriverAssitant_v5.12.zip` / `vivo9008drivers.exe` | 瑞芯微 / ADB 驱动 | 装驱动 |
| `模块/All-in-One.zip` | 整合模块 v2.1：开发者选项/adb/解除安装限制/显示档位/壁纸档位 + Helper App + **Amaze 文件管理器**（可装 APK） | Magisk 里刷 |

⚠️ 重打包必须：①保留结尾 second/DTB 区段 ②用正确算法重算 id 写入头部。重建用 `img/build_boot.py`（内置 `compute_boot_id()`，自动处理这两点）。

设备进刷机模式：关机，卡针顶住底部小孔不放，插 USB 连电脑。可能进 Loader 也可能进 Maskrom：

- Loader：直接能刷
- Maskrom：先用 `DB MiniLoaderAll.bin` 把 loader 下载进设备（MiniLoaderAll.bin 从 RKDevTool 的 Output/Android/Image 里拿，或用官方包解），下载完 RCI 能读到芯片信息就说明 loader 起来了，再执行刷写


## 完整操作流程（从零开始）

> 所有文件都在仓库内，按下面路径取。关键文件清单见文末"关键文件"表。

**① 关机 → 进 Loader**
- 卡针顶住底部小孔不放 + 插 USB 连电脑
- 设备管理器出现 Rockusb = 成功
- 驱动没装/不识别：装 `files/DriverAssitant_v5.12（瑞芯微驱动）.zip`（瑞芯微）和 `files/vivo9008drivers.exe`（通用 ADB）

**② 刷 boot**
- 双击 `一键流程.cmd` → `[1]`；或手动（工具 `upgrade_tool.exe`，镜像 `img/boot_SP523FC_S001014_magisk_root_adbmtp.img`）：
  ```
  upgrade_tool WL 0x14000 imgoot_SP523FC_S001014_magisk_root_adbmtp.img
  upgrade_tool WL 0x46000 imgoot_SP523FC_S001014_magisk_root_adbmtp.img
  upgrade_tool RD
  ```
- 设备在 Maskrom（无 loader）：脚本会自动用 `files/MiniLoaderAll.bin` 下载 loader

**③ 开机，插 USB**（boot 默认 `persist.sys.usb.config=adb`）
- adb 工具：根目录 `adb.exe`（连同 `AdbWinApi.dll`/`AdbWinUsbApi.dll`）

**④ 电脑连 adb**
```
adb devices
```
- `unauthorized` → 设备屏幕点"允许USB调试" → 变 `device`
- 验证 root：`adb shell su -c 'id'` → `uid=0`

**⑤ 装 Magisk 管理器**
```
adb install files\magisk_v28.1.apk
```
- 签名冲突：`adb uninstall com.topjohnwu.magisk` 后再 `adb install`

**⑥ 刷整合模块**
- Magisk → 模块 → 从本地安装 → `模块/All-in-One.zip` → 重启
- 功能：开发者选项(入口经 Helper 直达) / adb(USB+WiFi) / 解除安装限制 / 显示档位 / 壁纸档位，桌面出现 SP523FC Helper 可开关

**⑦ 完成，装应用**（用模块自带的 **Amaze 文件管理器**，它有安装权限）
- 桌面启动器：`files/E-Ink-Launcher（桌面启动器）.apk`
- 阅读器：`files/koreader-android-arm64-v2024.11.apk`

> 若第④步 adb 不出（个别机器 USB HAL 只认 MTP）：用 MTP 把 `模块/All-in-One.zip` 复制进设备，Magisk（改名版）→ 模块 → 本地安装 → 重启后 adb 由模块强制开启（USB + WiFi `adb connect 设备IP:5555`），再走⑤。

## 直接安装 APK（root 后的完整流程）

**1. Magisk 管理器**：`files/magisk_v28.1.apk` ——
- 已连 adb：`adb install files\magisk_v28.1.apk`
- 若提示"应用未安装/签名冲突"（设备上有 boot 里装的 stub，签名不同）：先 `adb uninstall com.topjohnwu.magisk` 再装
- 若 adb 不通：装好 All-in-One 模块后，用 **Amaze 文件管理器**（模块自带，已授权安装权限）点 APK 直接装，或 Helper App 的「扫描 /sdcard APK 并用 root 安装」（**本机自带文件管理器没有 REQUEST_INSTALL_PACKAGES 权限，无法直接装 APK**，见下方实测发现）

**2. All-in-One 模块**：`模块/All-in-One.zip` —— Magisk → 模块 → 从本地安装 → 选它 → 重启。功能：开发者选项（Helper 直达入口）/ adb / 解除安装限制 / 显示档位（亮度 10 级+反色+字体）/ 壁纸档位（001-005），桌面出现 "SP523FC Helper" App 可勾选开关。

**3. 装其他应用**：模块解除安装限制后，APK 复制到设备 → 文件管理器点击即可安装（不用再改名）。装系统应用白名单外的包名也能装。需要 root 的：装 Termux 之类的终端 App，`su` 即 root shell。

## 分区读保护和备份

loader 对 boot/super/vbmeta 等分区读保护，`rl` 读出来全 0xCC，设备侧做不了完整备份。这是 loader 的安全限制，没有公开的解锁方法（fastboot unlock 被签名质询挡着）。但 root 之后无所谓了，直接在系统里 dd 就行：

```
adb shell su -c 'dd if=/dev/block/by-name/super of=/sdcard/super.img bs=4096'
```

root 是绕过分区锁做备份最省事的办法。

## 真机实测发现（2026-08-25，adb 排查）

### 1. 为什么"系统已禁止安装该软件包"——文件管理器根本没有安装权限

从文件管理器装 APK 永远被拦，消息来自 ZUI 定制 PackageInstaller（`TC421_PackageInstaller.apk`）。根因：**`com.lenovo.louvre.filemanager` 的 manifest 里没有声明 `REQUEST_INSTALL_PACKAGES` 权限**（`appops get` 显示 "No operations"），PackageInstaller 的未知来源检查对未声明该权限的调用方直接拦截。而 `com.lenovo.louvre.appstore`（应用中心）声明且 `granted=true`。

- 这不是"未知来源开关"能解决的——appops 循环也救不了没声明权限的应用
- **已解决（2026-08-25）**：模块自带 **Amaze File Manager**（`com.amaze.filemanager`，开源，声明并授予了 `REQUEST_INSTALL_PACKAGES` + `MANAGE_EXTERNAL_STORAGE`），开机由 apply.sh root 强制安装并授权；另可随时用 `adb install` 或 Helper 的「root 安装 APK」

### 2. 开发者选项在设置里彻底隐藏（isSupportDoubleList 实测坐实）

- 连点"版本号"8 次无任何反应（`BuildNumberPreferenceController` 第一行被 `isSupportDoubleList()` 短路）
- `settings put secure/global development_settings_enabled 1` 后入口**依然不出现**
- `android.settings.APPLICATION_DEVELOPMENT_SETTINGS` intent 解析到 `DevelopmentSettingsDisabledActivity` 占位页（真 Activity 在 manifest 里 `enabled=false`，且 `pm enable` 需要 root，shell 无权）
- **可行方案**：模块开机以 root `pm enable` 真 Activity → Helper App「打开开发者选项」发同一 intent 直达

### 3. 亮度/色温的真实机制（RockchipLights HAL）

`logcat` 抓到的 HAL 日志（`vendor.light-rockchip`，前置灯为冷/暖双通道）：

```
setFL: brightness=9902, bright=48/48, ctemperature=3/2
setFL: brightness=9902, bright=48 warm=140, cold=214
```

- **亮度滑块 → `screen_brightness`（0-255）→ HAL `bright` 字段**；滑块是连续无级的（实测 0/44/105/169/242/253），不是固定几档
- **色温滑块 → HAL `warm/cold` 分光**（无 settings 键，Helper 无法直接控制，只能拖状态栏滑块）
- **前置灯有慢速平滑过渡**（`SmoothWarmingUp`/`SLOW_COLD_START_TIME`）：改亮度是渐变不是瞬变；亮度设很低会熄灯，重新点亮要等慢启动，`settings put` 直写偶尔会卡在过渡中途（如只到 bright=14）——UI 滑块路径最可靠
- 亮度写 `settings put system screen_brightness <0-255>` + `screen_brightness_mode 0` 在框架层生效（`mBrightnessState` 精确跟随）



## 和 SP101FU 的关系

同一块硬件板（Louvre_3566_4G），SP101FU 是 YOGA Paper（PRC），SP523FC 是启天 Smart Paper（CCN），固件不互通。SP101FU 的逆向结论（Settings 焊死、recovery-in-boot、分区读保护这些）对 SP523FC 一样适用，只是包和标识不同。详见 docs/SP101FU-YOGA-Paper/。

---
> **📜 版权声明**
> 本仓库所有内容（包括但不限于代码、文档、脚本）仅供学习参考。
> **未经作者书面授权，禁止任何形式的商用、转载、修改或二次分发。**
> 根据 GitHub Terms of Service，公开仓库允许 fork，但默认版权法保留所有权利。
