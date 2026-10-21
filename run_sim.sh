#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
testbench="${1:-tb_top}"
iverilog -g2005 -Wall -s "$testbench" -o "sim/$testbench.vvp" -c sources.f "tb/$testbench.v"
vvp "sim/$testbench.vvp"
