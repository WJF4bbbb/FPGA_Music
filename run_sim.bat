@echo off
setlocal
cd /d "%~dp0"
set "TB=%~1"
if "%TB%"=="" set "TB=tb_top"
set "SOURCE_LIST=tb/top_a_sources.f"
if /I "%TB%"=="tb_top" echo A-only integration: B/C are test-only interface substitutes.
if /I "%TB%"=="tb_clk_gen" (
    iverilog -g2001 -Wall -s %TB% -o sim/%TB%.vvp rtl/clk_gen.v tb/%TB%.v
) else (
    iverilog -g2001 -Wall -s %TB% -o sim/%TB%.vvp -c %SOURCE_LIST% tb/%TB%.v
)
if errorlevel 1 exit /b 1
vvp sim/%TB%.vvp
exit /b %errorlevel%
