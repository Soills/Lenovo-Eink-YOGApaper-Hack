#!/usr/bin/env bash
# ============================================================
# 部署解锁版 PackageInstaller（v2，安全版）—— 不碰 /system
#
# v1 教训：用「删系统 APK + 重启清记录」实测在这台带开机自检的机器上触发
# 进不去系统（整包重刷才恢复）。v2 彻底换方案：
#   * 不写 /system 磁盘文件 —— Magisk systemless 覆盖（内存挂载）
#   * 只动 /data —— 开机在 system_server 启动前清一次 packages.xml 旧签名记录
#     （post-fs-data.sh，带备份 + 自校验，坏了自动还原）
#   * 一次重启生效；回滚 = 卸载模块
#
# 前置：设备已 root（Magisk）。出厂包刷回后先刷 Magisk root boot 再跑。
#
# 用法:
#   bash install_unlocked.sh            部署（构建模块→装入→重启→校验）
#   bash install_unlocked.sh verify     只校验当前状态
#   bash install_unlocked.sh uninstall  回滚（清记录+移除模块）
# ============================================================
set -uo pipefail
cd "$(dirname "$0")"

ADB="${ADB:-../adb.exe}"
[ -f "$ADB" ] || ADB="$(command -v adb 2>/dev/null || echo adb)"
PKG=com.android.packageinstaller
UNLOCKED="PackageInstaller-unlocked.apk"
MOD_SRC="module"
MOD_ID="PiInstallerUnlocked"
MODDIR_DEV="/data/adb/modules/$MOD_ID"

xadb() { "$ADB" "$@"; }
die()  { echo "!! $*"; exit 1; }

wait_device() {
  echo "[*] 等待设备上线…"
  for _ in $(seq 1 180); do
    if xadb devices 2>/dev/null | grep -qi unauthorized; then
      echo "[!] 设备显示 unauthorized：请在设备上点「允许 USB 调试」并勾选始终允许"
      sleep 5
      continue
    fi
    xadb shell true 2>/dev/null && return 0
    sleep 5
  done
  die "设备迟迟不上线（USB adb 断了吗？）"
}

# 设备端命令失败也返回 0，避免 set -e/pipefail 误杀脚本
su_run() { xadb shell "su -c \"$1\"" 2>&1 | tr -d '\r' || true; }

require_root() {
  if ! su_run "id" | grep -q "uid=0"; then
    die "需要 root 但 su 被拒：先刷 Magisk root boot，并批准 Shell（Magisk → 超级用户）"
  fi
  if ! su_run "magisk -V 2>/dev/null" | grep -qE '^[0-9]+$'; then
    die "Magisk 未激活：先刷 Magisk root boot，装好 Magisk 管理器打开一次"
  fi
}

pkg_path() {
  xadb shell "pm path $PKG" 2>/dev/null | tr -d '\r' | sed -n 's/^package://p' || true
}

dev_hash() { su_run "sha256sum $1 2>/dev/null" | awk '{print $1}' || true; }

LOCAL_HASH=$(python -c "import hashlib;print(hashlib.sha256(open('$UNLOCKED','rb').read()).hexdigest())" 2>/dev/null || true)

module_installed() { su_run "test -f $MODDIR_DEV/module.prop && echo YES || echo NO" | grep -q YES; }

do_verify() {
  wait_device
  require_root
  local p h
  p=$(pkg_path)
  if [ -z "$p" ]; then
    echo "!! $PKG 记录不存在（模块没生效？先部署）"
    return 1
  fi
  h=$(dev_hash "$p")
  echo "包路径 : $p"
  echo "设备哈希: $h"
  echo "本地哈希: $LOCAL_HASH"
  if [ -n "$LOCAL_HASH" ] && [ "$h" = "$LOCAL_HASH" ]; then
    echo "✔ 解锁版 PackageInstaller 已生效"
    echo "  模块: $(module_installed && echo 已装入 || echo 未装入)"
    su_run "dumpsys package $PKG | grep -m1 versionName" | grep -v '^$' || true
    return 0
  else
    echo "!! 设备上是原版（哈希不匹配）"
    return 1
  fi
}

do_install() {
  require_root

  # 已生效则直接收尾
  if [ -n "$LOCAL_HASH" ] && [ "$(dev_hash "$(pkg_path)")" = "$LOCAL_HASH" ] 2>/dev/null; then
    echo "== 解锁版已生效，无需重复部署 =="
    do_verify
    return 0
  fi

  # 确认真实路径，并算出模块覆盖路径
  local real rel
  real=$(pkg_path)
  [ -n "$real" ] || die "pm path 为空（系统里没有 packageinstaller？出厂包应有）"
  rel=${real#/}
  case "$rel" in system/*) ;; *) rel="system/$rel" ;; esac
  echo "[*] 真机路径 : $real"
  echo "[*] 覆盖路径 : $MODDIR_DEV/$rel"

  # 旧模块先卸干净
  su_run "rm -rf $MODDIR_DEV" || true

  # 推文件到 /sdcard 暂存（FUSE 挂载，adb push 不会尝试 chown 报错；MSYS 用 // 转义）
  local base=/sdcard/Download/pi_mod
  su_run "rm -rf $base && mkdir -p $base && chmod 777 $base" || true
  xadb push "$MOD_SRC/module.prop"      //sdcard/Download/pi_mod/module.prop      >/dev/null || die "推送 module.prop 失败"
  xadb push "$MOD_SRC/post-fs-data.sh"  //sdcard/Download/pi_mod/post-fs-data.sh  >/dev/null || die "推送 post-fs-data.sh 失败"
  xadb push "$MOD_SRC/uninstall.sh"     //sdcard/Download/pi_mod/uninstall.sh     >/dev/null || die "推送 uninstall.sh 失败"
  xadb push "$UNLOCKED"                 //sdcard/Download/pi_mod/app.apk          >/dev/null || die "推送 APK 失败"

  # 设备端组装到 /data/adb/modules（mkdir 结构 + 权限）
  local apk_dir=${rel%/*}
  su_run "mkdir -p $MODDIR_DEV/$apk_dir \
    && cp $base/module.prop     $MODDIR_DEV/ \
    && cp $base/post-fs-data.sh $MODDIR_DEV/ \
    && cp $base/uninstall.sh    $MODDIR_DEV/ \
    && cp $base/app.apk         $MODDIR_DEV/$rel \
    && chmod 755 $MODDIR_DEV $MODDIR_DEV/$apk_dir \
    && chmod 644 $MODDIR_DEV/module.prop $MODDIR_DEV/$rel \
    && chmod 755 $MODDIR_DEV/post-fs-data.sh $MODDIR_DEV/uninstall.sh \
    && chown -R root:root $MODDIR_DEV \
    && rm -rf $base" || die "模块组装失败"

  if ! module_installed; then
    die "模块写入失败（/data/adb/modules 下找不到 module.prop）"
  fi
  echo "[*] 模块已装入。重启（1 次）后生效。"
  echo "[*] 重启设备…"
  xadb reboot >/dev/null 2>&1 || true
  wait_device

  # 等待 PM 起来
  for _ in $(seq 1 60); do
    xadb shell "pm path $PKG" >/dev/null 2>&1 && break
    sleep 5
  done
  echo "== 部署完成 =="
  do_verify
}

do_uninstall() {
  require_root
  echo "[*] 清记录（让原版重登记）"
  # 复用模块里的 uninstall.sh（同一个清记录逻辑）
  if module_installed; then
    xadb push "$MOD_SRC/uninstall.sh" //data/local/tmp/pi_uninstall.sh >/dev/null 2>&1 || true
    su_run "sh //data/local/tmp/pi_uninstall.sh; rm -f //data/local/tmp/pi_uninstall.sh"
  else
    su_run "rm -rf /data/data/$PKG /data/user/0/$PKG /data/user_de/0/$PKG 2>/dev/null" || true
    echo "   (模块未装入，只清包数据)"
  fi
  su_run "rm -rf $MODDIR_DEV" || true
  echo "[*] 已移除模块并清记录。重启后恢复原版 PackageInstaller。"
  xadb reboot >/dev/null 2>&1 || true
  wait_device
  echo "[*] 原版应已恢复。可用: bash install_unlocked.sh verify 检查（哈希会不匹配=原版，属正常）"
}

# ---------- 主流程 ----------
case "${1:-}" in
  verify)    do_verify; exit $? ;;
  uninstall) do_uninstall; exit 0 ;;
  *)         do_install ;;
esac
