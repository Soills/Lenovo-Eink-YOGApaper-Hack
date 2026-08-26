#!/system/bin/sh
# 移除模块时：清掉当前（解锁签名）记录，让 PM 下次启动用原版重新登记。
# 与 post-fs-data.sh 同逻辑（卸载时 overlay 还没摘除，要主动清）。
PKG=com.android.packageinstaller
PXML=/data/system/packages.xml
PLIST=/data/system/packages.list

sed "/name=\"$PKG\"/,/<\/package>/d" "$PXML" > "$PXML.tmp" 2>/dev/null
mv "$PXML.tmp" "$PXML" 2>/dev/null
sed "/^$PKG /d" "$PLIST" > "$PLIST.tmp" 2>/dev/null
mv "$PLIST.tmp" "$PLIST" 2>/dev/null
rm -rf "/data/data/$PKG" "/data/user/0/$PKG" "/data/user_de/0/$PKG" 2>/dev/null
exit 0
