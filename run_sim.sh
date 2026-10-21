#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
testbench="${1:-tb_top}"
if [[ "$testbench" == "tb_top" ]]; then
    echo "A-only integration: B/C are test-only interface substitutes."
fi
if [[ "$testbench" == "tb_clk_gen" ]]; then
    iverilog -g2001 -Wall -s "$testbench" -o "sim/$testbench.vvp" rtl/clk_gen.v "tb/$testbench.v"
else
    iverilog -g2001 -Wall -s "$testbench" -o "sim/$testbench.vvp" -c tb/top_a_sources.f "tb/$testbench.v"
fi
vvp "sim/$testbench.vvp"
