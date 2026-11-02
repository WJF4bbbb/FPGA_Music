#!/usr/bin/env bash
# ============================================================================
# check_bt_out.sh —— B 负责的回传链路一键自检
#
# 只检查我自己的东西，不碰队友的模块：
#   rtl/uart_tx.v       串口发送
#   rtl/telemetry.v     遥测打包
#   tb/tb_uart_tx.v     对应 testbench
#   tb/tb_telemetry.v   对应 testbench
#
# 用法：在 FPGA_Music 目录下执行
#   bash tools/check_bt_out.sh
#
# 退出码：0 = 全过，1 = 有问题
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0
ok()  { echo "  [OK]   $*"; PASS=$((PASS + 1)); }
bad() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

if ! command -v iverilog >/dev/null 2>&1; then
  echo "找不到 iverilog。请把 C:\\iverilog\\bin 加进 PATH 后重试。"
  exit 1
fi

mkdir -p sim
SRC=$(tr -d '\r' < sources.f | sed 's|^|./|')

echo "=== 1/3 双模式编译（查语法 + 不可综合写法） ==="
for mode in 2005 2012; do
  for tb in tb_uart_tx tb_telemetry; do
    if iverilog -g$mode -o "sim/$tb.$mode.vvp" -I tb -s "$tb" $SRC "tb/$tb.v" \
         2>"sim/$tb.$mode.err"; then
      ok "-g$mode  $tb 编译通过"
    else
      bad "-g$mode  $tb 编译失败"
      sed -n '1,6p' "sim/$tb.$mode.err" | sed 's/^/         /'
    fi
  done
done

echo
echo "=== 2/3 跑 testbench ==="
for mode in 2005 2012; do
  for tb in tb_uart_tx tb_telemetry; do
    [ -f "sim/$tb.$mode.vvp" ] || continue
    out=$(vvp "sim/$tb.$mode.vvp" 2>&1 | grep -viE '^VCD')
    if echo "$out" | grep -qi 'FAIL'; then
      bad "-g$mode  $tb 出现 FAIL"
      echo "$out" | grep -i 'FAIL' | head -3 | sed 's/^/         /'
    elif echo "$out" | grep -qi 'PASS'; then
      ok "-g$mode  $tb  $(echo "$out" | grep -i 'PASS' | tail -1 | sed 's/^ *//')"
    else
      bad "-g$mode  $tb 没有打印 PASS/FAIL"
      echo "$out" | tail -3 | sed 's/^/         /'
    fi
  done
done

echo
echo "=== 3/3 静态检查：RTL 里不能有仿真专用写法 ==="
for f in rtl/uart_tx.v rtl/telemetry.v; do
  hit=$(grep -nE '\$display|\$finish|\$monitor|\$stop|#[0-9]+' "$f" \
        | grep -vE '^[0-9]+:[[:space:]]*//' | head -3)
  if [ -z "$hit" ]; then
    ok "$f 干净"
  else
    bad "$f 含仿真专用写法（综合会忽略或报错）"
    echo "$hit" | sed 's/^/         /'
  fi
done

echo
echo "=================================================="
echo "  通过 $PASS 项，失败 $FAIL 项"
echo "=================================================="
if [ "$FAIL" -eq 0 ]; then
  echo "结论：后端没问题，可以烧板子验证真实链路"
  exit 0
else
  echo "结论：先修上面的 FAIL，再谈上板"
  exit 1
fi
