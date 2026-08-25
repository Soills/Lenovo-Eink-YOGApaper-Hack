#!/system/bin/sh
# SP523FC All-in-One service.sh — 开机自动应用档位配置
MODDIR=${0%/*}
[ -f "$MODDIR/apply.sh" ] && sh "$MODDIR/apply.sh" >/dev/null 2>&1
