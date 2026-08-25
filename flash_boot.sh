#!/bin/bash
# 刷 SP523FC root boot（bash 版，等价 一键流程.cmd [1]）
# 用法: Git Bash 里运行 ./flash_boot.sh
cd "$(dirname "$0")"
LOG=boot_flash.log
echo "=== waiting for Loader/Maskrom (max 10min) ===" > $LOG
MODE=""
for i in $(seq 1 120); do
  OUT=$(timeout 8 ./upgrade_tool.exe LD 2>&1 | tr -d '\r')
  if echo "$OUT" | grep -q "Mode=Loader"; then MODE=Loader; break; fi
  if echo "$OUT" | grep -q "Mode=Maskrom"; then MODE=Maskrom; break; fi
  sleep 5
done
if [ -z "$MODE" ]; then echo "TIMEOUT: no device" >> $LOG; exit 1; fi
echo "device mode: $MODE" >> $LOG
if [ "$MODE" = "Maskrom" ]; then
  ./upgrade_tool.exe DB files/MiniLoaderAll.bin >> $LOG 2>&1
  ./upgrade_tool.exe RCI >> $LOG 2>&1
fi
echo "=== WL boot_a (LBA 0x14000) ===" >> $LOG
./upgrade_tool.exe WL 0x14000 img/boot_SP523FC_S001014_magisk_root_adbmtp.img >> $LOG 2>&1
echo "WL_A_EXIT=$?" >> $LOG
echo "=== WL boot_b (LBA 0x46000) ===" >> $LOG
./upgrade_tool.exe WL 0x46000 img/boot_SP523FC_S001014_magisk_root_adbmtp.img >> $LOG 2>&1
echo "WL_B_EXIT=$?" >> $LOG
echo "=== RD reboot ===" >> $LOG
./upgrade_tool.exe RD >> $LOG 2>&1
echo "RD_EXIT=$?" >> $LOG
echo "=== ALL DONE ===" >> $LOG
