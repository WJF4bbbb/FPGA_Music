@echo off
setlocal
cd /d "%~dp0"
set "TB=%~1"
if "%TB%"=="" set "TB=tb_top"
iverilog -g2005 -Wall -s %TB% -o sim/%TB%.vvp -c sources.f tb/%TB%.v
if errorlevel 1 exit /b 1
vvp sim/%TB%.vvp
exit /b %errorlevel%
