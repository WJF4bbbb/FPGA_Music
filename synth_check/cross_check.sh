#!/usr/bin/env bash
# 交叉编译自检 —— 回答一个 tb 永远回答不了的问题：
#   "我的模块，能不能插进别人的整机顶层？"
#
# 为什么需要它：
#   自检 testbench 用的是**我自己**的接线，端口名写错也照样能跑通。
#   只有拿对方真实的 top.v 来编译，才能发现接口对不上。
#   2026-10-25 就是这样发现了 9 个 frame_tick 端口错误。
#
# 用法：
#   bash synth_check/cross_check.sh                    # 默认用 origin/feature/audio
#   bash synth_check/cross_check.sh origin/main        # 指定别的分支
#
# 做的事：
#   1) 从对方分支取出 rtl/ 下除 B 名下 5 个文件以外的全部源码
#   2) 配上**工作区里最新的** B 模块
#   3) 如果对方的 control_panel / sensor_frontend 还是 0 字节空文件，自动补最小桩
#   4) iverilog -s top 编译，两种语言模式各一次
#   5) 再用 test_enable=1 跑一段冒烟仿真，看 i2s_data 有没有真的在动
set -u
cd "$(dirname "$0")/.."

REF="${1:-origin/feature/audio}"
WORK="$(cygpath -m "$(mktemp -d)")/cross"
mkdir -p "$WORK/src"

MINE="osc.v sin_rom.v adsr.v mixer.v voice_alloc.v"

echo "交叉编译自检"
echo "  对方源码来自：$REF"
echo "  我的模块来自：工作区（未提交的改动也算）"
echo "  临时目录：    $WORK"
echo "------------------------------------------------------------"

if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
    echo "找不到分支 $REF，先 git fetch origin"
    exit 1
fi

# 1) 取对方的 rtl，跳过 B 的 5 个（用我的版本覆盖）
for f in $(git ls-tree -r --name-only "$REF" -- rtl/ | sed 's|^rtl/||'); do
    skip=0
    for m in $MINE; do [ "$f" = "$m" ] && skip=1; done
    [ "$skip" = "1" ] && continue
    git show "$REF:rtl/$f" > "$WORK/src/$f" 2>/dev/null
done

# 2) 我的模块用工作区最新版
for m in $MINE; do
    cp "rtl/$m" "$WORK/src/$m"
done

# 3) 空文件补桩（对方还没写的模块）
need_stub=0
for f in control_panel.v sensor_frontend.v; do
    if [ ! -s "$WORK/src/$f" ]; then
        need_stub=1
        echo "  注意：$f 是空文件，自动补最小桩"
    fi
done
if [ "$need_stub" = "1" ]; then
    cat > "$WORK/zz_stub.v" <<'STUB'
module control_panel (
    input wire clk, input wire rst_n,
    input wire timbre_key, input wire bend_up_key, input wire bend_down_key,
    input wire volume_up_key, input wire volume_down_key,
    output reg [1:0] timbre, output reg signed [3:0] bend, output reg [15:0] master_gain
);
    initial begin timbre = 2'd0; bend = 4'sd0; master_gain = 16'd65535; end
endmodule
module sensor_frontend (
    input wire clk, input wire rst_n, input wire [7:0] key_raw, output reg [7:0] key_state
);
    always @(posedge clk or negedge rst_n)
        if (!rst_n) key_state <= 8'd0; else key_state <= key_raw;
endmodule
STUB
    EXTRA="$WORK/zz_stub.v"
else
    EXTRA=""
fi

# 4) 编译
fail=0
for g in g2005 g2012; do
    printf "\n[编译] -%s -s top\n" "$g"
    out=$(iverilog -"$g" -s top -o "$WORK/top_$g.vvp" "$WORK"/src/*.v $EXTRA 2>&1)
    if [ -n "$out" ]; then
        echo "$out" | head -30
        echo "  >>> 编译失败"
        fail=1
    else
        echo "  ok  0 error"
    fi
done

[ "$fail" = "1" ] && { echo; echo "结果：接口对不上，先修上面列出的端口"; exit 1; }

# 5) 冒烟仿真：用对方自带的 test_mode 自动弹音，看 I2S 有没有数据
printf "\n[冒烟] test_enable=1，跑 300k 拍\n"
cat > "$WORK/smoke.v" <<'SMOKE'
`timescale 1ns/1ps
module smoke;
    reg clk = 0, rst_n = 0, test_enable = 1;
    reg [7:0] key_raw = 8'd0;
    reg timbre_key = 0, bend_up = 0, bend_down = 0, vol_up = 0, vol_down = 0;
    wire bclk, lrclk, i2s_data;
    integer toggles = 0, last_d = 1, frames = 0;
    always #5 clk = ~clk;
    top dut (.clk(clk), .rst_n(rst_n), .key_raw(key_raw),
             .timbre_key(timbre_key), .bend_up_key(bend_up), .bend_down_key(bend_down),
             .volume_up_key(vol_up), .volume_down_key(vol_down),
             .test_enable(test_enable), .bclk(bclk), .lrclk(lrclk), .i2s_data(i2s_data));
    always @(posedge clk) begin
        if (i2s_data !== last_d) begin toggles = toggles + 1; last_d = i2s_data; end
        if (dut.mixed_valid) frames = frames + 1;
    end
    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (300000) @(posedge clk);
        $display("SMOKE frames=%0d i2s_toggles=%0d", frames, toggles);
        $finish;
    end
endmodule
SMOKE
if iverilog -g2005 -s smoke -o "$WORK/smoke.vvp" "$WORK"/src/*.v $EXTRA "$WORK/smoke.v" 2>&1 | head -5; then
    res=$(vvp "$WORK/smoke.vvp" 2>/dev/null | grep SMOKE)
    echo "  $res"
    f=$(echo "$res" | sed -n 's/.*frames=\([0-9]*\).*/\1/p')
    t=$(echo "$res" | sed -n 's/.*i2s_toggles=\([0-9]*\).*/\1/p')
    if [ "${f:-0}" -gt 0 ] && [ "${t:-0}" -gt 100 ]; then
        echo "  ok  整机链路出声（mixer 出帧 + I2S 有数据）"
    else
        echo "  >>> 链路没出声。若编译是 0 error，问题多半在对方模块或前端桩，不一定是你的"
        fail=1
    fi
fi

echo "------------------------------------------------------------"
if [ "$fail" = "0" ]; then
    echo "结果：通过（接口对得上，且整机能出声）"
else
    echo "结果：未通过"
fi
exit "$fail"
