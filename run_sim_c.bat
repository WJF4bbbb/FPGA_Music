@echo off
setlocal
cd /d "%~dp0"
REM C-group unit tests: each C RTL compiled with its own testbench only.
REM iVerilog is bundled at D:\iverilog\bin (override with the IVL env var).
if not defined IVL set "IVL=D:\iverilog\bin"
set "PATH=%IVL%;%PATH%"
set "FAIL=0"

echo === tb_sensor_frontend ===
iverilog -g2001 -Wall -s tb_sensor_frontend -o sim/tb_sensor_frontend.vvp rtl/sensor_frontend.v tb/tb_sensor_frontend.v
if errorlevel 1 (set "FAIL=1") else (vvp sim/tb_sensor_frontend.vvp || set "FAIL=1")

echo === tb_control_panel ===
iverilog -g2001 -Wall -s tb_control_panel -o sim/tb_control_panel.vvp rtl/control_panel.v tb/tb_control_panel.v
if errorlevel 1 (set "FAIL=1") else (vvp sim/tb_control_panel.vvp || set "FAIL=1")

echo === tb_note_event ===
iverilog -g2001 -Wall -s tb_note_event -o sim/tb_note_event.vvp rtl/note_event.v tb/tb_note_event.v
if errorlevel 1 (set "FAIL=1") else (vvp sim/tb_note_event.vvp || set "FAIL=1")

if "%FAIL%"=="0" (echo ALL C TESTS PASSED) else (echo SOME C TESTS FAILED)
exit /b %FAIL%
