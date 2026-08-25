# 界面转储 / UI dumps（2026-08-25 真机 uiautomator）

本目录保存测试时从设备抓取的 UI 层级转储（`uiautomator dump` 产物），用于逆向和排查时对照界面结构。文件为 XML，含每个控件的 text / class / bounds。

| 文件 | 界面 | 用途 |
|---|---|---|
| [01-设置主页-settings-main.xml](01-设置主页-settings-main.xml) | ZUI 设置主页（设置/联想帐号/WLAN/蓝牙/声音/显示/通用…） | 确认设置入口列表，**无开发者选项** |
| [02-关于本机-about-device.xml](02-关于本机-about-device.xml) | 通用 → 关于本机 | 版本号位置（连点 8 次无反应 = isSupportDoubleList 短路） |
| [03-状态栏快捷面板-quick-settings.xml](03-状态栏快捷面板-quick-settings.xml) | 状态栏快捷面板 | **亮度 / 色温 两个 SeekBar** + 全局/清晰/快速/流畅 刷新模式 + 自动调节亮度 |
| [04-桌面-launcher.xml](04-桌面-launcher.xml) | ZUI 桌面 | 已安装应用列表（含 Magisk / SP523FC 壁纸 / SP523FC Helper） |
| [05-Helper-v1-helper-v1.xml](05-Helper-v1-helper-v1.xml) | Helper App v1 界面 | 旧版（3 档亮度） |
| [06-Helper-v2-helper-v2.xml](06-Helper-v2-helper-v2.xml) | Helper App v2 界面 | 新版（快捷入口 / 10 档亮度 / 壁纸档位） |
| [07-安装被禁-install-blocked.xml](07-安装被禁-install-blocked.xml) | PackageInstaller 拦截对话框 | "系统已禁止安装该软件包" 证据（文件管理器无 REQUEST_INSTALL_PACKAGES） |

> 原始抓取共 23 个，内容去重后保留以上 7 个有参考价值的；设备端 `/sdcard/*.xml` 已清理。
