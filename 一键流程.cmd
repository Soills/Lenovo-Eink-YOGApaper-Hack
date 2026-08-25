@echo off
chcp 936 >nul
title SP523FC 刷机脚本
setlocal EnableExtensions
cd /d "%~dp0"

REM ============================================================
REM  SP523FC (启天 Smart Paper) 刷机脚本
REM  更新: 2026-08-25
REM  说明: 刷 Magisk root boot + 原版恢复 + 整包刷机
REM
REM  img\ 目录:
REM    boot_SP523FC_S001014_magisk_root_adbmtp.img   root boot (主用, 已实测可开机)
REM    boot_SP523FC_S001014_original.img             完整原厂 boot (恢复用)
REM  files\ 目录: MiniLoaderAll.bin / magisk_v28.1.apk / 驱动
REM  模块\ 目录: All-in-One.zip (装完 boot 后在 Magisk 里刷)
REM ============================================================

set "TOOL=%~dp0upgrade_tool.exe"
if not exist "%TOOL%" set "TOOL=%~dp0tool\upgrade_tool.exe"
if not exist "%TOOL%" (
    echo [错误] 找不到 upgrade_tool.exe
    echo 请把它放在本目录, 或本目录 tool\ 子目录下。
    echo.
    pause
    exit /b 1
)

:menu
cls
echo ============================================================
echo   SP523FC 刷机脚本
echo.
echo   [1] 刷 root boot (Magisk + 默认 USB adb)
echo   [2] 刷回官方原版 boot
echo   [3] 整包刷机 (官方原包, 防砖/恢复)
echo   [4] 说明 / 安装模块
echo   [0] 退出
echo ============================================================
choice /c 12340 /m "请选择"
if errorlevel 5 exit /b 0
if errorlevel 4 goto :info
if errorlevel 3 goto :full
if errorlevel 2 goto :flash_stock
goto :flash_root

REM ===================== 刷 root boot =====================
:flash_root
cls
echo ============================================================
echo   [1] 刷 root + 开发者模式 boot
echo ============================================================
echo.
echo   前置条件:
echo     1. 设备关机
echo     2. 卡针顶住底部小孔不放, 同时插 USB 连电脑
echo     3. 设备管理器出现 Rockusb 设备 = 已进入 Loader/Maskrom
echo.
echo   此操作只刷 boot 分区, 不清数据, 不影响系统。
echo.
choice /c YN /m "确认已进入 Loader 模式? (Y=继续  N=返回)"
if errorlevel 2 goto :menu

set "BOOTIMG=%~dp0img\boot_SP523FC_S001014_magisk_root_adbmtp.img"
if not exist "%BOOTIMG%" (
    echo [错误] 找不到 %BOOTIMG%
    echo 请确认 img\ 目录下存在该文件。
    echo.
    pause
    goto :menu
)

echo.
echo ==== [1/4] 检测设备 ====
"%TOOL%" LD > "%~dp0rk_mode.tmp"
findstr /C:"No found" "%~dp0rk_mode.tmp" >nul
if not errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    goto :nodev
)
findstr "Maskrom" "%~dp0rk_mode.tmp" >nul
if errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    echo 设备在 Loader 模式, 直接继续...
    goto :ldr_ok2
)
echo 设备处于 Maskrom 模式, 先下载 loader...
if not exist "%~dp0files\MiniLoaderAll.bin" (
    echo [错误] 找不到 files\MiniLoaderAll.bin
    del /q "%~dp0rk_mode.tmp"
    pause
    goto :menu
)
"%TOOL%" DB "%~dp0files\MiniLoaderAll.bin"
if errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    goto :fail
)
echo 已下载 loader...
"%TOOL%" RCI
del /q "%~dp0rk_mode.tmp"
:ldr_ok2

echo.
echo ==== [2/4] 查看分区表 ====
"%TOOL%" PL

echo.
echo ==== [3/4] 写入 boot 分区 ====
echo   目标: %BOOTIMG%
echo   写入中, 途中请勿断开!
echo   写入 boot_a (LBA 0x14000) ...
"%TOOL%" WL 0x14000 "%BOOTIMG%"
if errorlevel 1 goto :fail
echo   写入 boot_b (LBA 0x46000) ...
"%TOOL%" WL 0x46000 "%BOOTIMG%"
if errorlevel 1 goto :fail

echo.
echo ==== [4/4] 完成 ====
echo.
echo ============================================================
echo   刷写完成!
echo.
echo   接下来:
echo     1. 开机, 插 USB (默认就是 adb 模式, 屏幕点"允许USB调试")
echo     2. adb devices 确认连接
echo     3. 装 Magisk 管理器:  adb install files\magisk_v28.1.apk
echo        (若提示签名冲突, 先 adb uninstall com.topjohnwu.magisk)
echo     4. 刷整合模块:  Magisk -> 模块 -> 从本地安装 -> 模块\All-in-One.zip
echo        重启后解锁开发者选项 / 解除安装限制等
echo ============================================================
choice /c YN /m "是否重启设备? (Y=重启  N=以后手动)"
if errorlevel 2 goto :menu
"%TOOL%" RD
echo 已发送重启指令, 设备正在启动...
echo.
pause
goto :menu

REM ===================== 刷回原版 boot =====================
:flash_stock
cls
echo ============================================================
echo   [2] 刷回官方原版 boot
echo ============================================================
echo.
echo   恢复原版 boot (无 root / 无 adb), 用于出厂恢复。
echo   前置条件同 [1]: 关机 + 卡针顶住 + 插 USB 进 Loader 模式。
echo.
choice /c YN /m "确认已进入 Loader 模式? (Y=继续  N=返回)"
if errorlevel 2 goto :menu

set "BOOTIMG=%~dp0img\boot_SP523FC_S001014_original.img"
if not exist "%BOOTIMG%" (
    echo [错误] 找不到 %BOOTIMG%
    pause
    goto :menu
)

echo.
echo ==== [1/3] 检测设备 ====
"%TOOL%" LD > "%~dp0rk_mode.tmp"
findstr /C:"No found" "%~dp0rk_mode.tmp" >nul
if not errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    goto :nodev
)
findstr "Maskrom" "%~dp0rk_mode.tmp" >nul
if errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    echo 设备在 Loader 模式, 直接继续...
    goto :ldr_ok3
)
echo 设备处于 Maskrom 模式, 先下载 loader...
if not exist "%~dp0files\MiniLoaderAll.bin" (
    echo [错误] 找不到 files\MiniLoaderAll.bin
    del /q "%~dp0rk_mode.tmp"
    pause
    goto :menu
)
"%TOOL%" DB "%~dp0files\MiniLoaderAll.bin"
if errorlevel 1 (
    del /q "%~dp0rk_mode.tmp"
    goto :fail
)
echo 已下载 loader...
"%TOOL%" RCI
del /q "%~dp0rk_mode.tmp"
:ldr_ok3

echo.
echo ==== [2/3] 写入原版 boot ====
echo   写入 boot_a (LBA 0x14000) ...
"%TOOL%" WL 0x14000 "%BOOTIMG%"
if errorlevel 1 goto :fail
echo   写入 boot_b (LBA 0x46000) ...
"%TOOL%" WL 0x46000 "%BOOTIMG%"
if errorlevel 1 goto :fail

echo.
echo ==== [3/3] 完成 ====
echo   已刷回官方原版 boot。
choice /c YN /m "是否重启设备? (Y=重启  N=以后手动)"
if errorlevel 2 goto :menu
"%TOOL%" RD
echo 已发送重启指令...
echo.
pause
goto :menu

REM ===================== 整包刷机 (防砖) =====================
:full
cls
echo ============================================================
echo   [3] 整包刷机 (防砖/恢复出厂)
echo ============================================================
echo.
echo   使用 SP523FC 原厂固件整包刷写:
echo     %~dp0..\SP523FC_USR_S001014_2303011705_RK3566_CN\image\update_nowaveform.img
echo.
echo   注意:
echo     - 整包刷机会覆盖所有分区, 通常也会清掉用户数据
echo     - 这是"刷砖了救活"的最后手段
echo     - 刷回 S001014 系统后, 再刷 [1] 的 root boot 即可恢复 root
echo.
set "PKG=%~dp0..\SP523FC_USR_S001014_2303011705_RK3566_CN\image\update_nowaveform.img"
if not exist "%PKG%" (
    echo [错误] 找不到原厂包:
    echo   %PKG%
    echo   请确认 SP523FC_USR_S001014_2303011705_RK3566_CN 目录在原包位置。
    echo.
    pause
    goto :menu
)
echo 前置条件同 [1]: 关机 + 卡针顶住 + 插 USB 进 Loader 模式。
choice /c YN /m "确认整包刷机? (Y=继续  N=返回)"
if errorlevel 2 goto :menu

echo.
echo ==== [1/2] 检测设备 ====
"%TOOL%" LD
"%TOOL%" RCI
if errorlevel 1 goto :nodev

echo.
echo ==== [2/2] 整包刷写 (耗时较长, 勿断连/断电) ====
"%TOOL%" uf "%PKG%"

echo.
echo 刷写结束后显示 Upgrade firmware ok 即成功。
echo 若未自动开机, 请长按电源键重启。
echo.
pause
goto :menu

REM ===================== 说明 =====================
:info
cls
echo ============================================================
echo   说明 / 安装模块
echo ============================================================
echo.
echo   这个 boot 里有什么?
echo     1. Magisk v28.1 (root)
echo        - init 替换为 magiskinit, 开机自动 root
echo        - 装管理器:  adb install files\magisk_v28.1.apk
echo     2. 默认 USB=adb
echo        - prop.default: persist.sys.usb.config=adb
echo        - 开机后插 USB 即 adb, 屏幕点"允许USB调试"
echo.
echo   装完 root 后做什么?
echo     Magisk 管理器 -> 模块 -> 从本地安装 -> 模块\All-in-One.zip
echo     该模块一键解锁: 开发者选项 / adb / 解除安装限制 / 壁纸替换
echo     自带设置界面 App (SP523FC Helper), 可开关各功能
echo.
echo   为什么之前很多 boot 刷了开不了机?
echo     根因有两个, 都已在 build_boot.py 解决:
echo     1. 重打包丢了 boot 结尾的 second/DTB 设备树区段 -> 内核无设备树
echo     2. uboot 对 boot 做 SHA1 校验, 和头部 id 比对, 必须用正确算法重算
echo     详见 docs/SP523FC-QiTian/README.md
echo.
echo   刷完没 adb 怎么办?
echo     a. 确认刷的是 [1] 的 root boot (含 USB adb 配置)
echo     b. 插 USB 后 adb devices, 显示 unauthorized 就在设备屏幕点允许
echo     c. 还不行: 装 All-in-One 模块后, WiFi adb: adb connect 设备IP:5555
echo.
echo   常用文件:
echo     img\boot_SP523FC_S001014_magisk_root_adbmtp.img   root boot (主用)
echo     img\boot_SP523FC_S001014_original.img            完整原厂 boot (恢复)
echo     files\magisk_v28.1.apk                           Magisk 管理器
echo     files\MiniLoaderAll.bin                           Maskrom 模式恢复 loader
echo     模块\All-in-One.zip                               整合功能模块
echo.
pause
goto :menu

REM ===================== 错误处理 =====================
:nodev
echo.
echo [失败] 未检测到设备, 请检查:
echo   1. 设备是否在 Loader/Maskrom 模式 (卡针顶住 + USB)
echo   2. 驱动是否安装 (DriverAssitant 瑞芯微驱动)
echo   3. USB 口/线是否可靠 (优先直连主板后置 USB)
echo.
pause
goto :menu

:fail
echo.
echo [失败] 写入未成功, 请检查:
echo   1. 设备是否一直处于 Loader 模式 (途中断开需重新进)
echo   2. USB 口/线是否可靠
echo   3. 镜像文件是否完整 (img\ 目录下文件大小是否正常)
echo.
pause
goto :menu
