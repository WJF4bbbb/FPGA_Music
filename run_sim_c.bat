@echo off
setlocal
cd /d "%~dp0"
REM C-group unit tests: each C RTL compiled with its own testbench only.
REM IVL selects one installation for BOTH tools. Fall back to the legacy path
REM or the compiler on PATH. OSS CAD Suite also needs its matching lib DLLs.
if not defined IVL if exist "D:\iverilog\bin\iverilog.exe" set "IVL=D:\iverilog\bin"
if not defined IVL for /f "delims=" %%I in ('where iverilog.exe 2^>nul') do if not defined IVL set "IVL=%%~dpI"
if not defined IVL (echo ERROR: Set IVL to the Icarus bin directory. & exit /b 2)
for %%I in ("%IVL%\.") do set "IVL=%%~fI"
if not exist "%IVL%\iverilog.exe" (echo ERROR: Missing "%IVL%\iverilog.exe" & exit /b 2)
if not exist "%IVL%\vvp.exe" (echo ERROR: Missing "%IVL%\vvp.exe" & exit /b 2)
set "PATH=%IVL%;%IVL%\..\lib;%PATH%"
echo Icarus bin: %IVL%
set "FAIL=0"

call :run tb_sensor_frontend sensor_frontend
call :run tb_control_panel control_panel
call :run tb_note_event note_event

if "%FAIL%"=="0" (echo ALL C TESTS PASSED) else (echo SOME C TESTS FAILED)
exit /b %FAIL%

:run
echo === %~1 ===
"%IVL%\iverilog.exe" -g2001 -Wall -s %~1 -o sim/%~1.vvp rtl/%~2.v tb/%~1.v
if errorlevel 1 (set "FAIL=1" & exit /b 0)
"%IVL%\vvp.exe" "sim\%~1.vvp" > "sim\%~1.tmp" 2>&1
if errorlevel 1 set "FAIL=1"
type "sim\%~1.tmp"
REM Older C testbenches call $finish even on failure: check their real output.
findstr /b /c:"FAIL" "sim\%~1.tmp" >nul
if not errorlevel 1 set "FAIL=1"
findstr /x /c:"PASS: %~1 all checks passed" "sim\%~1.tmp" >nul
if errorlevel 1 set "FAIL=1"
exit /b 0
