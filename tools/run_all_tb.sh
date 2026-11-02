#!/usr/bin/env bash
# ============================================================================
# run_all_tb.sh —— 全量回归：把仓库里所有 testbench 跑一遍
#
# 用法（在 FPGA_Music 目录下）：
#   bash tools/run_all_tb.sh           # 只跑 -g2012，约 18 分钟
#   bash tools/run_all_tb.sh both      # -g2005 和 -g2012 都跑，约 25 分钟
#   bash tools/run_all_tb.sh fast      # 跳过最慢的 tb_top_integration，约 18 分钟
#   bash tools/run_all_tb.sh full      # 连 tb_top_integration 一起跑，约 30 分钟
#
# 时间都花在两个大件上（其余 20 多个加起来不到 1 分钟）：
#   tb_ttp229_latency    约 12 分钟，全速率 32 个用例 —— **烧板子前必须跑**
#   tb_top_integration   约 13 分钟，整树 VCD —— 只在改了集成逻辑时跑
#
# 分组说明：
#   模块级  —— 只编被测模块，隔离性好，出问题一定是我改的东西
#   顶层级  —— 编整棵源码树，验证集成后还能跑
#   特殊    —— tb_top 自带桩模块（用 tb/top_a_sources.f 单独编）；
#              tb_bt_at_init 属于独立的 at_cfg 工程，不进 sources.f
#
# 退出码：0 = 全过
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1

MODES="2012"
FAST=1                     # 默认跳过 tb_top_integration；加 full 才跑
for a in "$@"; do
  [ "$a" = "both" ] && MODES="2005 2012"
  [ "$a" = "fast" ] && FAST=1
  [ "$a" = "full" ] && FAST=0
done

if ! command -v iverilog >/dev/null 2>&1; then
  echo "找不到 iverilog。请把 C:\\iverilog\\bin 加进 PATH。"
  exit 1
fi

mkdir -p sim
SRC=$(tr -d '\r' < sources.f | sed 's|^|./|')
ASRC=$(tr -d '\r' < tb/top_a_sources.f | sed 's|^|./|')

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  [OK]    $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL]  $*"; FAIL=$((FAIL+1)); }
skip() { echo "  [SKIP]  $*"; SKIP=$((SKIP+1)); }

# 判定"真的失败"：大写 FAIL 作为独立词出现，且同一行里没有 PASS。
# 为什么要这么写：tb_bt_at_init 会打印"重试 3 次后 fail 拉高"，
# 小写 fail 是描述不是结论；tb_adsr 等会打印"=== PASS (0 errors) ==="，
# 里面有 error 也是通过。用 grep -i 一刀切会误判。
is_fail() {
  grep -E '(^|[^A-Za-z_])FAIL([^A-Za-z_]|$)' | grep -v 'PASS'
}

# observe <tb名> <源文件列表> <模式>
# 观察型 testbench：只打印数字给人看，本身不判 PASS/FAIL。
# 只要编得过、跑得完、没报错，就算它没问题。
observe() {
  tb=$1; src=$2; mode=$3
  vvp_file="sim/$tb.$mode.vvp"
  if ! iverilog -g$mode -I tb -s "$tb" -o "$vvp_file" $src "tb/$tb.v" \
        2>"sim/$tb.$mode.err"; then
    bad "-g$mode  $tb  编译失败"
    sed -n '1,4p' "sim/$tb.$mode.err" | sed 's/^/          /'
    return
  fi
  out=$(vvp "$vvp_file" 2>&1 | grep -viE '^VCD')
  hit=$(echo "$out" | is_fail | head -3)
  if [ -n "$hit" ]; then
    bad "-g$mode  $tb  运行报错"
    echo "$hit" | sed 's/^/          /'
  else
    skip "-g$mode  $tb  观察型，无 PASS/FAIL（看 sim/$tb.$mode.out）"
    echo "$out" > "sim/$tb.$mode.out"
  fi
}

# run_one <tb名> <源文件列表> <模式>
run_one() {
  tb=$1; src=$2; mode=$3
  vvp_file="sim/$tb.$mode.vvp"
  if ! iverilog -g$mode -I tb -s "$tb" -o "$vvp_file" $src "tb/$tb.v" \
        2>"sim/$tb.$mode.err"; then
    bad "-g$mode  $tb  编译失败"
    sed -n '1,4p' "sim/$tb.$mode.err" | sed 's/^/          /'
    return
  fi
  out=$(vvp "$vvp_file" 2>&1 | grep -viE '^VCD')
  hit=$(echo "$out" | is_fail | head -3)
  if [ -n "$hit" ]; then
    bad "-g$mode  $tb  运行出现 FAIL"
    echo "$hit" | sed 's/^/          /'
  elif echo "$out" | grep -qi 'PASS'; then
    ok "-g$mode  $tb  $(echo "$out" | grep -i 'PASS' | tail -1 | sed 's/^ *//')"
  else
    bad "-g$mode  $tb  没有打印 PASS/FAIL"
    echo "$out" | tail -3 | sed 's/^/          /'
  fi
}

echo "=================================================="
echo " 全量回归  （模式：-g$MODES）"
echo "=================================================="

echo
echo "---------- RTL 双模式编译（可综合代码，必须两种都过） ----------"
# 主工程 17 个 RTL + A 的 AT 配置工具 2 个（后者不进主工程，单独编）
ATSRC="./rtl/bt_at_init.v ./rtl/top_at_cfg.v"
for mode in 2005 2012; do
  if iverilog -g$mode -o /dev/null $SRC $ATSRC 2>"sim/rtl.$mode.err"; then
    ok "-g$mode  整棵 RTL 编译通过（含 at_cfg 工具）"
  else
    bad "-g$mode  整棵 RTL 编译失败"
    sed -n '1,5p' "sim/rtl.$mode.err" | sed 's/^/          /'
  fi
done
echo "  说明：部分 testbench 用了 SystemVerilog 的 task 多语句和尺寸转换，"
echo "        只能在 -g2012 下编。这是 testbench 的写法，不是 RTL 的问题。"

for mode in $MODES; do
  echo
  echo "---------- -g$mode  模块级 ----------"
  run_one tb_control_panel   "./rtl/control_panel.v"                          $mode
  run_one tb_uart_rx         "./rtl/uart_rx.v"                                $mode
  run_one tb_uart_tx         "./rtl/uart_tx.v"                                $mode
  run_one tb_bt_cmd_parse    "./rtl/bt_cmd_parse.v"                           $mode
  run_one tb_telemetry       "./rtl/telemetry.v ./rtl/uart_tx.v"              $mode
  run_one tb_osc_timbre      "./rtl/osc.v ./rtl/sin_rom.v"                    $mode
  observe tb_osc             "./rtl/osc.v ./rtl/sin_rom.v"                    $mode
  run_one tb_note_event      "./rtl/note_event.v"                             $mode
  run_one tb_sensor_frontend "./rtl/sensor_frontend.v"                        $mode
  run_one tb_ttp229_reader   "./rtl/ttp229_reader.v tb/ttp229_model.v"        $mode
  run_one tb_adsr            "./rtl/adsr.v"                                   $mode
  run_one tb_mixer           "./rtl/mixer.v"                                  $mode
  run_one tb_voice_alloc     "./rtl/voice_alloc.v"                            $mode
  run_one tb_i2s_tx          "./rtl/i2s_tx.v ./rtl/audio_timing.v"            $mode
  run_one tb_audio_timing    "./rtl/audio_timing.v"                           $mode
  run_one tb_test_mode       "./rtl/test_mode.v"                              $mode

  echo
  echo "---------- -g$mode  顶层级（整棵源码树） ----------"
  run_one tb_top_board_inputs   "$SRC ./tb/ttp229_model.v"                    $mode
  run_one tb_top_pa_enable      "$SRC ./tb/ttp229_model.v"                    $mode
  run_one tb_top_input_polarity "$SRC ./tb/ttp229_model.v"                    $mode
  if [ "$FAST" -eq 1 ]; then
    skip "-g$mode  tb_top_integration  慢（整树 VCD，约 10 分钟），fast 模式跳过"
  else
    run_one tb_top_integration    "$SRC ./tb/ttp229_model.v"                  $mode
  fi
  run_one tb_top_bt_in          "$SRC ./tb/ttp229_model.v"                    $mode
  run_one tb_ttp229_latency     "$SRC ./tb/ttp229_model.v"                    $mode
  run_one tb_chain              "$SRC ./tb/ttp229_model.v"                    $mode
  run_one tb_contract_boundaries "$SRC ./tb/ttp229_model.v"                   $mode
  echo
  echo "---------- -g$mode  特殊（自带桩模块 / 独立顶层） ----------"
  run_one tb_top "$ASRC" $mode
  # A 的 AT 配置工具：独立工程，不进 sources.f，单独编
  run_one tb_bt_at_init "./rtl/bt_at_init.v ./rtl/uart_rx.v" $mode
done

echo
echo "=================================================="
printf "  通过 %d   失败 %d   跳过 %d\n" "$PASS" "$FAIL" "$SKIP"
echo "=================================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
