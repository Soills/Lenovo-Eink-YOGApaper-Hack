#!/bin/bash
# 构建 SP523FC Helper APK（无资源、纯代码 UI，v1 签名，适合 Magisk 模块 system/app）
# 依赖: JDK 17 + Android build-tools(aapt2/zipalign/lib/d8.jar) + platform android.jar
# 用法: TOOLCHAIN=/d/rk_toolchain ./build.sh
set -e
cd "$(dirname "$0")"

TOOLCHAIN="${TOOLCHAIN:-/d/rk_toolchain}"
AAPT2="$TOOLCHAIN/android-14/aapt2.exe"
ZIPALIGN="$TOOLCHAIN/android-14/zipalign.exe"
D8JAR="$TOOLCHAIN/android-14/lib/d8.jar"
ANDROID_JAR="$TOOLCHAIN/android-11/android.jar"

OUT="$(pwd)/build"
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/dex" src/assets
# 内嵌模块 apply.sh，使 Helper 在模块未安装时也能 root 即时生效
cp ../All-in-One/apply.sh src/assets/apply.sh

echo "== aapt2 link =="
"$AAPT2" link -o "$OUT/Helper-unsigned.apk" \
  -I "$ANDROID_JAR" \
  --manifest AndroidManifest.xml \
  -A src/assets \
  --min-sdk-version 23 --target-sdk-version 30

echo "== javac =="
javac -encoding UTF-8 -source 8 -target 8 \
  -bootclasspath "$ANDROID_JAR" \
  -d "$OUT/classes" \
  src/com/sp523fc/helper/*.java

echo "== d8 =="
java -cp "$D8JAR" com.android.tools.r8.D8 \
  --min-api 23 --lib "$ANDROID_JAR" \
  --output "$OUT/dex" \
  $(find "$OUT/classes" -name '*.class')

echo "== add classes.dex =="
PYTHONIOENCODING=utf-8 python - "$OUT" <<'PY'
import sys, zipfile, os
out = sys.argv[1]
apk = os.path.join(out, 'Helper-unsigned.apk')
dex = os.path.join(out, 'dex', 'classes.dex')
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(dex, 'classes.dex')
print('classes.dex added')
PY

echo "== zipalign =="
"$ZIPALIGN" -f 4 "$OUT/Helper-unsigned.apk" "$OUT/Helper-aligned.apk"

echo "== sign (apksigner v1+v2) =="
KS="$(pwd)/keystore/testkey.jks"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -alias sp523fc \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android \
    -dname "CN=SP523FC Helper" -noprompt >/dev/null 2>&1
fi
APKSIGNER="$TOOLCHAIN/android-14/apksigner.bat"
"$APKSIGNER" sign --ks "$KS" --ks-pass pass:android \
  --out "$OUT/SP523FC-Helper.apk" "$OUT/Helper-aligned.apk"

echo "== done =="
"$APKSIGNER" verify "$OUT/SP523FC-Helper.apk"
ls -la "$OUT/SP523FC-Helper.apk"
