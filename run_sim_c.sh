#!/usr/bin/env bash
# C-group unit tests: each C RTL compiled with its own testbench only.
# iVerilog is bundled at /d/iverilog/bin (override with the IVL env var).
set -euo pipefail
cd "$(dirname "$0")"
IVL="${IVL:-/d/iverilog/bin}"
export PATH="$IVL:$PATH"
fail=0
run() {
  echo "=== $1 ==="
  iverilog -g2001 -Wall -s "$1" -o "sim/$1.vvp" "rtl/${1#tb_}.v" "tb/$1.v" || fail=1
  vvp "sim/$1.vvp" || fail=1
}
run tb_sensor_frontend
run tb_control_panel
run tb_note_event
if [ "$fail" -eq 0 ]; then echo "ALL C TESTS PASSED"; else echo "SOME C TESTS FAILED"; fi
exit $fail
