# pi.apk —— PackageInstaller 解锁

`pi.apk` 是联想墨水屏（ZUI）定制版系统安装器 `com.android.packageinstaller`（AOSP 1.0.0.011）。
反编译发现它带**两道安装限制**（都在 `PackageInstallerActivity` 里）：

| 门槛 | 逻辑 | 拦截文案 |
|---|---|---|
| ① 安装白名单 `checkWhiteListApps()` | PRC 地区：只允许装「已安装过的应用」；其他地区（如 SP523FC=CCN）：包名必须在 `/system/etc/lenovoapps.xml` 的 `white-list` 里且 `<region>` 含设备地区 | 「系统已禁止安装该软件包。」（EinkTipsDialog） |
| ② 未知来源 `REQUEST_INSTALL_PACKAGES` appop | 调用方无授权就拦 | 「出于安全考虑…」（AOSP 对话框） |

> ⚠️ 之前 docs 里把「系统已禁止安装该软件包」归因于 appop——**不对**：该文案只属于白名单门槛
> （`install_failed_blocked`），appop 门槛是另一句文案。模块之前的 `appops` 放行只能过②，过不了①。

## 解锁产物

- `PackageInstaller-unlocked.apk` —— 签名后的解锁 APK（新签名密钥，非原厂）
- `PiInstaller-unlocked-v1.0.zip` —— Magisk 模块，覆盖 `/system/priv-app/TC421_PackageInstaller/TC421_PackageInstaller.apk`（真机实测该路径）
- `patch.py` —— smali 补丁（可复现）
- `make_module.py` —— 重建模块（连上设备会自动按 `pm path` 校正路径）
- `apktool_out/` —— apktool 反汇编目录；`decompiled/` —— jadx 反编译目录

## 改了什么（patch.py）

1. `checkWhiteListApps()` → 直接 `return true`（白名单整体作废）
2. `checkIfAllowedAndInitiateInstall()` 开头置 `mAllowUnknownSources = true`（未知来源/appop 检查短路）
3. **保留** `no_install_apps` 管理员限制（MDM 策略，个人设备不触发）

## 安装步骤（安全版 v2，不碰 /system，root 即可）

> ⚠️ **v2 换方案（2026-08-26）**：v1 用「删系统 APK + 重启清记录」，实测在这台带开机自检
> 的机器上触发进不去系统（整包重刷才恢复）。v2 彻底不写 /system 磁盘文件：
> **Magisk systemless 覆盖**（内存挂载，原文件原封不动）+ 开机在 system_server 启动前清一次
> packages.xml 旧签名记录（`post-fs-data.sh`，只动 /data，带备份自校验）。一次重启生效，回滚=卸载模块。

1. **先刷 Magisk root boot**（`一键流程.cmd` [1]），装好 Magisk 管理器并激活
2. 确认 Magisk 已给 shell 授权（Magisk → 超级用户 → 批准 Shell）
3. `bash install_unlocked.sh` —— 自动：构建模块 → 装入 `/data/adb/modules` → 重启 → 校验
4. 自校验通过即完成。任意 APK 点开直接装，不再弹「系统已禁止安装该软件包」

回滚：`bash install_unlocked.sh uninstall`（清记录 + 移除模块，重启后原版重新登记）。

> 为什么不能 `pm install` / 必须换签名：系统应用换签名后 PM 用 packages.xml 旧签名比对会忽略
> 新 APK；`pm install` 覆盖被签名检查拒；装成普通应用丢掉 INSTALL_PACKAGES 特权、安装流程会挂。
> 正解就是 systemless 覆盖 + 开机清一次记录——不碰 /system，风险最低。

## 签名说明

解锁版用 uber-apk-signer 自动生成的测试密钥签名（v2+v3，SHA256withRSA，2044 到期）。
Magisk 覆盖挂载路径与原版一致，privapp 权限白名单（无 signer 限制）照常生效，系统权限不丢。
