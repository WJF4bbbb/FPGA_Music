#!/usr/bin/env bash
# 跑 B 名下全部模块的仿真自检。
#   bash run_b_tb.sh          # 默认用 -g2005
#   bash run_b_tb.sh g2012    # 用 -g2012（和 tb_osc.v 注释里的一致）
#
# 每个 tb 都会打印 PASS / FAIL 和具体数值，不需要看波形就能判断对错。
set -uo pipefail
cd "$(dirname "$0")"

G="${1:-g2005}"
fail=0

run() {
    local tb="$1"; shift
    printf "\n===================== %s (-%s) =====================\n" "$tb" "$G"
    if ! iverilog -"$G" -s "$tb" -o "sim/$tb.vvp" "$@" "tb/$tb.v" 2> >(grep -v -i "timescale\|time precision\|design elements\|Affected\|declared here" >&2); then
        echo "  *** COMPILE FAILED ***"
        fail=1
        return
    fi
    vvp "sim/$tb.vvp" || fail=1
}

run tb_mixer        rtl/mixer.v
run tb_adsr         rtl/adsr.v
run tb_voice_alloc  rtl/voice_alloc.v
run tb_osc_timbre   rtl/osc.v rtl/sin_rom.v
run tb_chain        rtl/voice_alloc.v rtl/osc.v rtl/sin_rom.v rtl/adsr.v rtl/mixer.v

printf "\n=====================================================\n"
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS (-$G)"
else
    echo "SOME TESTS FAILED (-$G)"
fi
exit "$fail"
