#!/system/bin/sh
# SP523FC All-in-One apply.sh
# 读取档位配置并应用。由 service.sh（开机）和 SP523FC Helper App（即时）调用。
# 配置来源优先级: Helper App 私有目录 > 模块默认 config

MODDIR=/data/adb/modules/sp523fc_allinone
APPCFG=/data/data/com.sp523fc.helper/files/config
CFG="$MODDIR/config"
[ -f "$APPCFG" ] && CFG="$APPCFG"
[ -f "$CFG" ] && . "$CFG"

# ===== 默认值（全开，等同旧版行为）=====
DEV_OPTIONS=${DEV_OPTIONS:-1}
ADB=${ADB:-1}
INSTALL=${INSTALL:-1}
COMMON=${COMMON:-1}
INVERT=${INVERT:-0}
BRIGHT=${BRIGHT:-0}
FONT=${FONT:-1.0}
WALLPAPER=${WALLPAPER:-1}

# ===== 1. 开发者选项档位 =====
if [ "$DEV_OPTIONS" = "1" ]; then
  pm enable 'com.android.settings/com.android.settings.Settings$DevelopmentSettingsDashboardActivity' 2>/dev/null
  pm enable 'com.android.settings/.Settings$DevelopmentSettingsDashboardActivity' 2>/dev/null
  settings put global development_settings_enabled 1
  settings put secure development_settings_enabled 1
else
  settings put global development_settings_enabled 0
  settings put secure development_settings_enabled 0
fi

# ===== 2. ADB 档位（USB + WiFi）=====
if [ "$ADB" = "1" ]; then
  settings put global adb_enabled 1
  setprop persist.sys.usb.config adb
  setprop persist.adb.tcp.port 5555
  setprop sys.usb.config none
  setprop sys.usb.config adb
  stop adbd 2>/dev/null
  start adbd 2>/dev/null
else
  settings put global adb_enabled 0
  setprop sys.usb.config mtp
fi

# ===== 3. 解除安装限制档位 =====
if [ "$INSTALL" = "1" ]; then
  settings put secure install_non_market_apps 1
  settings put global package_verifier_enable 0
  settings put global verifier_verify_adb_installs 0
  settings put global verifier_disable_adb_installs 1
  for pkg in $(pm list packages 2>/dev/null | sed 's/package://'); do
    appops set "$pkg" REQUEST_INSTALL_PACKAGES allow 2>/dev/null
  done
fi

# ===== 4. 常用设置档位 =====
if [ "$COMMON" = "1" ]; then
  settings put global stay_on_while_plugged_in 3
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
fi

# ===== 5. 显示档位（亮度 / 深色反色 / 字体）=====
if [ "$INVERT" = "1" ]; then
  settings put secure accessibility_display_inversion_enabled 1
else
  settings put secure accessibility_display_inversion_enabled 0
fi
case "$BRIGHT" in
  ""|0) ;;   # 0=不调整
  *)
    settings put system screen_brightness "$BRIGHT"
    settings put system screen_brightness_mode 0
    ;;
esac
settings put system font_scale "$FONT"

# ===== 6. 壁纸档位：00N.png -> 当前生效的 001.png =====
if [ "$WALLPAPER" -ge 1 ] 2>/dev/null && [ "$WALLPAPER" -le 9 ]; then
  if [ "$WALLPAPER" != "1" ]; then
    SRC="$MODDIR/system/product/etc/tpc_res/wallpaper/00${WALLPAPER}.png"
    DST="$MODDIR/system/product/etc/tpc_res/wallpaper/001.png"
    [ -f "$SRC" ] && cp -f "$SRC" "$DST" && chmod 644 "$DST"
  fi
fi

# ===== 7. 文件管理器（Amaze，声明 REQUEST_INSTALL_PACKAGES 可装 APK）=====
# 开机强制安装 + 授权；本机自带文件管理器无安装权限，装 APK 必须用这个
APK="$MODDIR/system/app/AmazeFileManager/AmazeFileManager.apk"
if [ -f "$APK" ]; then
  pm install -r "$APK" 2>/dev/null
  appops set com.amaze.filemanager REQUEST_INSTALL_PACKAGES allow 2>/dev/null
  appops set com.amaze.filemanager MANAGE_EXTERNAL_STORAGE allow 2>/dev/null
fi

echo "OK: DEV=$DEV_OPTIONS ADB=$ADB INSTALL=$INSTALL COMMON=$COMMON INVERT=$INVERT BRIGHT=$BRIGHT FONT=$FONT WALLPAPER=$WALLPAPER"
