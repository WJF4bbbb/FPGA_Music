#!/usr/bin/env bash
# 综合自检 —— 只查 B 名下 4 个模块，不碰整机 top.v
#
# 干什么：把 osc / sin_rom / adsr / mixer / voice_alloc 接成一个临时顶层 b_top，
#         交给高云综合器（GowinSynthesis）跑一遍，回答两个问题：
#           ① 这些代码能不能变成真电路（有没有不可综合的写法）
#           ② 占多少 LUT / REG / DSP / BSRAM（写报告要用）
#
# 为什么不在仓库目录里直接跑：高云命令行工具不认中文路径，
#         仓库路径含"竞赛/嵌赛"，会被吞成 ??? 然后报 Cannot open Verilog file。
#         所以先拷到纯英文的临时目录再综合，源文件一个字节都不动。
#
# 用法：
#   bash synth_check/run_synth.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
GW_SH="/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe"

if [ ! -x "$GW_SH" ]; then
    echo "找不到 gw_sh：$GW_SH"
    echo "请确认高云 EDA 装在 C:/Gowin/Gowin_V1.9.12.03_x64"
    exit 1
fi

WORK="$(cygpath -m "$(mktemp -d)")/b_synth_check"
mkdir -p "$WORK/src"
cp "$REPO"/rtl/osc.v "$REPO"/rtl/sin_rom.v "$REPO"/rtl/adsr.v \
   "$REPO"/rtl/mixer.v "$REPO"/rtl/voice_alloc.v "$WORK/src/"
cp "$HERE"/b_top.v "$WORK/"

cat > "$WORK/run.tcl" <<EOF
create_project -name b_check -dir "$WORK/prj" -pn GW2A-LV18QN88C8/I7 -device_version C -force
add_file "$WORK/b_top.v"
add_file "$WORK/src/osc.v"
add_file "$WORK/src/sin_rom.v"
add_file "$WORK/src/adsr.v"
add_file "$WORK/src/mixer.v"
add_file "$WORK/src/voice_alloc.v"
set_option -top_module b_top
set_option -print_all_synthesis_warning 1
run syn
exit
EOF

echo "临时工程：$WORK"
echo "------------------------------------------------------------"
"$GW_SH" "$WORK/run.tcl" 2>&1 | tee "$WORK/synth.log"
echo "------------------------------------------------------------"

if grep -q "^ERROR" "$WORK/synth.log"; then
    echo "结果：综合失败，看上面的 ERROR 行"
    exit 1
fi

RSC="$WORK/prj/b_check/impl/gwsynthesis/b_check_syn_rsc.xml"
echo "结果：综合通过"
echo
echo "===== 资源占用（T_ 开头是含子模块的累计值）====="
if [ -f "$RSC" ]; then
    cat "$RSC"
else
    echo "没找到资源报告：$RSC"
fi
echo
echo "报告目录：$WORK/prj/b_check/impl/gwsynthesis/"
