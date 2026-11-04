@echo off
title FPGA Synth - Bluetooth Bridge
cd /d "%~dp0.."

set "PY="
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python311\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Launcher\py.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Launcher\py.exe"
if not defined PY if exist "C:\Python313\python.exe" set "PY=C:\Python313\python.exe"
if not defined PY if exist "C:\Python312\python.exe" set "PY=C:\Python312\python.exe"
if not defined PY if exist "C:\Program Files\Python313\python.exe" set "PY=C:\Program Files\Python313\python.exe"
if not defined PY where python >nul 2>nul
if not defined PY if %errorlevel%==0 set "PY=python"
if not defined PY where py >nul 2>nul
if not defined PY if %errorlevel%==0 set "PY=py"

if not defined PY (
  echo ============================================================
  echo  [ERROR] Python not found on this computer.
  echo.
  echo  Install Python 3 from https://www.python.org/downloads/
  echo  and tick "Add python.exe to PATH" during setup.
  echo ============================================================
  pause
  exit /b 1
)

echo ============================================================
echo   FPGA Synth - Bluetooth Bridge
echo ============================================================
echo.
echo   Using: %PY%
echo.
echo   Step 1  Pick the paired module below. Press Enter = first.
echo   Step 2  When you see "bridge started", open this URL:
echo.
echo              http://localhost:8765/web/bridge.html
echo.
echo   Closing this window disconnects the bridge.
echo ============================================================
echo.

"%PY%" tools\bt_bridge.py %*

echo.
echo ------------------------------------------------------------
echo  Bridge exited. Common causes:
echo    no paired device  - pair the HC-05 in Windows Settings first
echo    port in use       - an old bridge window is still open
echo ------------------------------------------------------------
pause >nul
