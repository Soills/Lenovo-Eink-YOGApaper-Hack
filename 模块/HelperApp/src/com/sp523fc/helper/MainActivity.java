package com.sp523fc.helper;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * SP523FC Helper — All-in-One 模块的设置 App。
 *
 * 开关/档位写入本应用私有目录 config（root 在开机时可读），然后经
 * su 调用模块 apply.sh 立即生效（无 root 时保存，重启后由 service.sh 生效）。
 *
 * 实测结论（2026-08-25 真机）:
 *  - 状态栏亮度滑块 -> settings screen_brightness -> RockchipLights HAL（前置灯，慢速平滑过渡）
 *  - 色温滑块走 HAL 内部 cold/warm，无 settings 键，Helper 无法直接控制
 *  - 本机文件管理器无 REQUEST_INSTALL_PACKAGES 权限 -> 安装被"系统已禁止安装该软件包"拦截
 *    -> 本 App 提供 root 方式 pm install 绕开
 */
public class MainActivity extends Activity {

    static final String MODDIR = "/data/adb/modules/sp523fc_allinone";
    static final String CFG = "/data/data/com.sp523fc.helper/files/config";

    static final String[] KEYS = {
        "DEV_OPTIONS", "ADB", "INSTALL", "COMMON",
        "INVERT", "BRIGHT", "FONT", "WALLPAPER"
    };
    static final String[] DEFAULTS = {
        "1", "1", "1", "1",
        "0", "0", "1.0", "1"
    };

    private final Map<String, String> cfg = new HashMap<String, String>();
    private LinearLayout root;
    private TextView status;
    private CheckBox chkDev, chkAdb, chkInstall, chkCommon;
    private LinearLayout apkList;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(28, 28, 28, 28);
        setContentView(root);

        TextView title = new TextView(this);
        title.setText("SP523FC Helper");
        title.setTextSize(22);
        title.setGravity(Gravity.CENTER);
        root.addView(title);

        TextView sub = new TextView(this);
        sub.setText("All-in-One v2 · 档位开关即时生效");
        sub.setTextSize(13);
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, 4, 0, 8);
        root.addView(sub);

        // ---- 快捷入口 ----
        section("快捷入口 / Shortcuts");
        addRow("打开开发者选项（需模块已启用其 Activity）", "OPEN_DEV");
        addRow("扫描 /sdcard 的 APK 并用 root 安装", "SCAN_APK");

        // ---- 功能档位 ----
        section("功能档位 / Feature tiers");
        chkDev = addCheck("开发者选项 (Developer options)", "DEV_OPTIONS");
        chkAdb = addCheck("ADB (USB + WiFi)", "ADB");
        chkInstall = addCheck("解除安装限制 (Install restrictions)", "INSTALL");
        chkCommon = addCheck("常用设置 (Stay awake + no animations)", "COMMON");
        final CheckBox[] grp = new CheckBox[]{chkDev, chkAdb, chkInstall, chkCommon};
        addRow("基础档（仅开发者选项）", new int[]{1,0,0,0}, grp);
        addRow("常用档（+ADB+解除限制）", new int[]{1,1,1,0}, grp);
        addRow("全开档（全部）", new int[]{1,1,1,1}, grp);

        // ---- 显示档位 ----
        section("显示档位 / Display levels");
        final String[] brights = {"10", "30", "60", "90", "120", "150", "180", "210", "240", "255"};
        final String[] brightLabels = {
            "亮度 10%（最暗）", "亮度 30%", "亮度 60%", "亮度 90%",
            "亮度 120", "亮度 150", "亮度 180", "亮度 210", "亮度 240", "亮度 255（最亮）"
        };
        for (int i = 0; i < brights.length; i++) {
            addRow(brightLabels[i], "BRIGHT", brights[i]);
        }
        addRow("深色/反色：关", "INVERT", "0");
        addRow("深色/反色：开", "INVERT", "1");
        addRow("字体：标准", "FONT", "1.0");
        addRow("字体：大", "FONT", "1.15");
        addRow("字体：特大", "FONT", "1.3");
        addRow("（色温需在状态栏 色温 滑块调节，无 settings 接口）", "NONE", "");

        // ---- 壁纸档位 ----
        section("壁纸档位 / Wallpaper slots");
        for (int i = 1; i <= 5; i++) {
            addRow("应用壁纸 00" + i + ".png", "WALLPAPER", String.valueOf(i));
        }

        // ---- root 安装 APK 结果区 ----
        apkList = new LinearLayout(this);
        apkList.setOrientation(LinearLayout.VERTICAL);
        root.addView(apkList);

        status = new TextView(this);
        status.setTextSize(13);
        status.setPadding(0, 24, 0, 0);
        root.addView(status);

        loadCfg();
        refreshChecks();
        status.setText("切换后立即应用；未授权 root 时保存，重启后生效");
    }

    private void section(String title) {
        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(17);
        t.setPadding(0, 26, 0, 6);
        root.addView(t);
    }

    private CheckBox addCheck(String label, final String key) {
        final CheckBox cb = new CheckBox(this);
        cb.setText(label);
        cb.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                cfg.put(key, cb.isChecked() ? "1" : "0");
                saveCfg();
                apply();
            }
        });
        root.addView(cb);
        return cb;
    }

    private void addRow(final String label, final String key) {
        addRow(label, key, "");
    }

    private void addRow(final String label, final String key, final String value) {
        Button btn = new Button(this);
        btn.setText(label);
        btn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                if ("OPEN_DEV".equals(key)) {
                    openDevSettings();
                } else if ("SCAN_APK".equals(key)) {
                    scanApks();
                } else {
                    cfg.put(key, value);
                    saveCfg();
                    refreshChecks();
                    apply();
                }
            }
        });
        root.addView(btn);
    }

    private void addRow(String label, final int[] vals, final CheckBox[] grp) {
        Button btn = new Button(this);
        btn.setText(label);
        btn.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                for (int i = 0; i < 4; i++) {
                    cfg.put(KEYS[i], String.valueOf(vals[i]));
                }
                saveCfg();
                refreshChecks();
                apply();
            }
        });
        root.addView(btn);
    }

    private void refreshChecks() {
        chkDev.setChecked("1".equals(cfg.get("DEV_OPTIONS")));
        chkAdb.setChecked("1".equals(cfg.get("ADB")));
        chkInstall.setChecked("1".equals(cfg.get("INSTALL")));
        chkCommon.setChecked("1".equals(cfg.get("COMMON")));
    }

    private void loadCfg() {
        for (int i = 0; i < KEYS.length; i++) cfg.put(KEYS[i], DEFAULTS[i]);
        try {
            BufferedReader r = new BufferedReader(new FileReader(CFG));
            String line;
            while ((line = r.readLine()) != null) {
                int eq = line.indexOf('=');
                if (eq > 0) cfg.put(line.substring(0, eq).trim(), line.substring(eq + 1).trim());
            }
            r.close();
        } catch (IOException ignored) {
        }
    }

    private void saveCfg() {
        try {
            File f = new File(CFG);
            FileOutputStream o = new FileOutputStream(f);
            StringBuilder sb = new StringBuilder();
            for (String k : KEYS) sb.append(k).append('=').append(cfg.get(k)).append('\n');
            o.write(sb.toString().getBytes("UTF-8"));
            o.close();
        } catch (IOException e) {
            runOnUiThread(new Runnable() { public void run() { status.setText("保存失败: " + e); } });
        }
    }

    private void apply() {
        status.setText("正在应用…");
        ensureScript();
        final String script = new File(getFilesDir(), "apply.sh").getAbsolutePath();
        new Thread(new Runnable() {
            public void run() {
                String out = exec("su", "-c", "sh " + script);
                final String msg = (out == null)
                        ? "未获取 root，已保存，重启后由 service.sh 生效"
                        : out.trim();
                runOnUiThread(new Runnable() { public void run() { status.setText(msg); } });
            }
        }).start();
    }

    /** 内嵌 apply.sh（与模块同一份）解到私有目录，模块未装时也能 root 即时生效 */
    private void ensureScript() {
        try {
            File f = new File(getFilesDir(), "apply.sh");
            if (f.exists()) return;
            InputStream is = getAssets().open("apply.sh");
            FileOutputStream os = new FileOutputStream(f);
            byte[] buf = new byte[8192];
            int n;
            while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
            is.close();
            os.close();
        } catch (IOException ignored) {
        }
    }

    private void openDevSettings() {
        try {
            startActivity(new Intent("android.settings.APPLICATION_DEVELOPMENT_SETTINGS"));
        } catch (Exception e) {
            status.setText("打开开发者选项失败: " + e);
        }
    }

    private void scanApks() {
        apkList.removeAllViews();
        status.setText("正在扫描 /sdcard 的 APK…");
        new Thread(new Runnable() {
            public void run() {
                String out = exec("su", "-c",
                        "ls -1 /sdcard/*.apk /sdcard/Download/*.apk /sdcard/*/*.apk 2>/dev/null");
                if (out == null) {
                    runOnUiThread(new Runnable() { public void run() { status.setText("未获取 root，无法扫描"); } });
                    return;
                }
                final List<String> apks = new ArrayList<String>();
                for (String line : out.split("\n")) {
                    line = line.trim();
                    if (line.endsWith(".apk")) apks.add(line);
                }
                runOnUiThread(new Runnable() {
                    public void run() {
                        if (apks.isEmpty()) {
                            status.setText("未在 /sdcard 找到 APK（放入 /sdcard 根目录或 Download）");
                            return;
                        }
                        status.setText("找到 " + apks.size() + " 个 APK，点击安装：");
                        for (final String p : apks) {
                            Button b = new Button(MainActivity.this);
                            b.setText(p.replace("/sdcard/", ""));
                            b.setOnClickListener(new View.OnClickListener() {
                                public void onClick(View v) { installApk(p); }
                            });
                            apkList.addView(b);
                        }
                    }
                });
            }
        }).start();
    }

    private void installApk(final String path) {
        status.setText("正在安装 " + path + " …");
        new Thread(new Runnable() {
            public void run() {
                String out = exec("su", "-c", "pm install -r '" + path + "' 2>&1");
                final String msg = (out == null) ? "未获取 root" : out.trim();
                runOnUiThread(new Runnable() { public void run() { status.setText(msg); } });
            }
        }).start();
    }

    private String exec(String... cmd) {
        try {
            Process p = Runtime.getRuntime().exec(cmd);
            InputStream is = p.getInputStream();
            InputStream es = p.getErrorStream();
            BufferedReader r = new BufferedReader(new InputStreamReader(is));
            BufferedReader e = new BufferedReader(new InputStreamReader(es));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
            while ((line = e.readLine()) != null) sb.append(line).append('\n');
            p.waitFor();
            return sb.toString();
        } catch (Exception ex) {
            return null;
        }
    }
}
