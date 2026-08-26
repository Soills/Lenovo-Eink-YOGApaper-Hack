# -*- coding: utf-8 -*-
"""构建 PiInstaller-unlocked Magisk 模块 zip。
自动从真机读取 com.android.packageinstaller 的实际安装路径，
把解锁版 APK 放到模块里对应的覆盖路径（路径不对 Magisk 覆盖不生效）。
设备没连时按默认路径（/system/priv-app/TC421_PackageInstaller/）构建并警告。
"""
import os
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ADB = os.path.join(HERE, "..", "adb.exe")
APK = os.path.join(HERE, "PackageInstaller-unlocked.apk")
MOD = os.path.join(HERE, "module")
OUT = os.path.join(HERE, "PiInstaller-unlocked-v1.0.zip")
PKG = "com.android.packageinstaller"
DEFAULT_REL = "system/priv-app/TC421_PackageInstaller/TC421_PackageInstaller.apk"


def run_adb(*args):
    exe = ADB if os.path.exists(ADB) else shutil.which("adb")
    if not exe:
        return None
    try:
        r = subprocess.run([exe] + list(args), capture_output=True, text=True, timeout=15)
        return r.stdout
    except Exception:
        return None


def real_path_on_device():
    out = run_adb("shell", "pm", "path", PKG)
    if not out:
        return None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("package:"):
            return line[len("package:"):]
    return None


def to_module_rel(real):
    rel = real.lstrip("/")
    if not rel.startswith("system/"):
        rel = "system/" + rel
    return rel


def build(rel):
    tmp = os.path.join(HERE, ".module_tmp")
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    shutil.copytree(MOD, tmp)
    for root, _dirs, files in os.walk(tmp):
        for f in files:
            if f.endswith(".apk"):
                os.remove(os.path.join(root, f))
    dst = os.path.join(tmp, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(APK, dst)
    if os.path.exists(OUT):
        os.remove(OUT)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(tmp):
            for f in files:
                p = os.path.join(root, f)
                arc = os.path.relpath(p, tmp)
                z.write(p, arc)
    shutil.rmtree(tmp)
    return dst


def main():
    if not os.path.exists(APK):
        print("找不到 %s，先运行补丁流程生成解锁 APK" % os.path.basename(APK))
        sys.exit(1)
    if not os.path.exists(os.path.join(MOD, "module.prop")):
        print("找不到 module/module.prop")
        sys.exit(1)

    real = real_path_on_device()
    if real:
        rel = to_module_rel(real)
        print("真机路径 : %s" % real)
        print("模块路径 : %s" % rel)
        dst = build(rel)
        print("已把解锁 APK 放进模块: %s" % rel)
    else:
        print("未连设备/取不到路径，按默认路径构建（若 Magisk 覆盖不生效，请连上设备重跑本脚本）")
        dst = build(DEFAULT_REL)
        print("模块路径 : %s" % DEFAULT_REL)
    print("模块已生成: %s" % OUT)
    print()
    print("下一步（出厂包刷回后，安全版 v2，不碰 /system）：")
    print("  1. 先刷 Magisk root boot（一键流程.cmd [1]），装好 Magisk 管理器并激活")
    print("  2. 确认 Magisk 已给 shell 授权（Magisk → 超级用户 → 批准 Shell）")
    print("  3. bash install_unlocked.sh  —— 构建模块→装入→重启→校验（systemless 覆盖，一次重启生效）")
    print("     回滚：bash install_unlocked.sh uninstall")


if __name__ == "__main__":
    main()
