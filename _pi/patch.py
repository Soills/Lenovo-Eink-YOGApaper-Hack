# -*- coding: utf-8 -*-
"""Patch pi.apk (ZUI PackageInstaller) smali:
1. checkWhiteListApps() always returns true  ->  whitelist gate removed
2. checkIfAllowedAndInitiateInstall() sets mAllowUnknownSources=true
   at entry  ->  unknown-source / appop gate short-circuits.
no_install_apps (MDM) restriction is intentionally kept.
"""
import io
import sys

BASE = sys.argv[1] if len(sys.argv) > 1 else "apktool_out"
PATH = BASE + "/smali/com/android/packageinstaller/PackageInstallerActivity.smali"

with io.open(PATH, "r", encoding="utf-8") as f:
    lines = f.readlines()

# ---- locate checkWhiteListApps()Z block ----
start = None
for i, ln in enumerate(lines):
    if ln.startswith(".method private checkWhiteListApps()Z"):
        start = i
        break
assert start is not None, "checkWhiteListApps not found"

end = None
for i in range(start + 1, len(lines)):
    if lines[i].strip() == ".end method":
        end = i
        break
assert end is not None, "checkWhiteListApps .end method not found"

new_method = [
    ".method private checkWhiteListApps()Z\n",
    "    .locals 1\n",
    "\n",
    "    const/4 v0, 0x1\n",
    "\n",
    "    return v0\n",
    ".end method\n",
]

lines[start : end + 1] = new_method

# ---- patch checkIfAllowedAndInitiateInstall()V : set mAllowUnknownSources=true ----
start = None
for i, ln in enumerate(lines):
    if ln.startswith(".method private checkIfAllowedAndInitiateInstall()V"):
        start = i
        break
assert start is not None, "checkIfAllowedAndInitiateInstall not found"

# insert right after ".locals N"
ins = None
for i in range(start + 1, start + 6):
    if lines[i].startswith("    .locals "):
        ins = i + 1
        break
assert ins is not None, ".locals line not found"

inject = [
    "\n",
    "    const/4 v0, 0x1\n",
    "\n",
    "    iput-boolean v0, p0, Lcom/android/packageinstaller/PackageInstallerActivity;->mAllowUnknownSources:Z\n",
    "\n",
]
lines[ins:ins] = inject

with io.open(PATH, "w", encoding="utf-8", newline="\n") as f:
    f.writelines(lines)

print("OK: checkWhiteListApps -> return true; mAllowUnknownSources forced true")
