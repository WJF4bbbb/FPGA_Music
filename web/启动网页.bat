@echo off
chcp 65001 >nul
title FPGA 合成器 · 本地网页服务
cd /d "%~dp0.."

echo ================================================
echo   FPGA 合成器  蓝牙控制台
echo ================================================
echo.
echo   网址:  http://localhost:8000/web/index.html
echo.
echo   浏览器已经自动打开，没打开就手动复制上面那行。
echo   关掉这个黑窗口 = 停止服务。
echo ================================================
echo.

start "" "http://localhost:8000/web/index.html"
python -m http.server 8000

echo.
echo 服务已停止。按任意键关闭。
pause >nul
