#!/system/bin/sh
# All-in-One —— PackageInstaller 解锁：清旧签名记录（systemless 覆盖版专用）
#
# 模块覆盖了 /system/priv-app/TC421_PackageInstaller/ 下的解锁版 APK（不写 /system
# 磁盘文件）。换签名后 PM 会拿 packages.xml 旧签名比对、忽略新 APK，所以这里在
# system_server 启动前删掉该包旧条目，让 PM 以新签名重新登记。只动 /data，带备份+自校验。
# 幂等：.done 标记。配合 systemless 覆盖，一次重启生效，卸载模块即回滚。

MODDIR=${0%/*}
PKG=com.android.packageinstaller
PXML=/data/system/packages.xml
PLIST=/data/system/packages.list

[ -f "$MODDIR/.pi_done" ] && exit 0

[ -f "$MODDIR/packages.xml.bak" ]  || cp -a "$PXML"  "$MODDIR/packages.xml.bak"  2>/dev/null
[ -f "$MODDIR/packages.list.bak" ] || cp -a "$PLIST" "$MODDIR/packages.list.bak" 2>/dev/null

# 删 packages.xml 里的包块（从 name= 匹配行到 </package>），toybox 兼容（不用 sed -i）
sed "/name=\"$PKG\"/,/<\/package>/d" "$PXML" > "$PXML.tmp" 2>/dev/null
mv "$PXML.tmp" "$PXML" 2>/dev/null

# 删 packages.list 里对应行
sed "/^$PKG /d" "$PLIST" > "$PLIST.tmp" 2>/dev/null
mv "$PLIST.tmp" "$PLIST" 2>/dev/null

# 清包数据
rm -rf "/data/data/$PKG" "/data/user/0/$PKG" "/data/user_de/0/$PKG" 2>/dev/null

# 自校验：packages.xml 应仍以 <packages 开头；否则还原
if ! head -c 64 "$PXML" 2>/dev/null | grep -q "<packages"; then
    [ -f "$MODDIR/packages.xml.bak" ] && cp -a "$MODDIR/packages.xml.bak" "$PXML"
    exit 0
fi

touch "$MODDIR/.pi_done"
exit 0
