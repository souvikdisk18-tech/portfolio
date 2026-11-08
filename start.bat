@echo off
title Suman Garai Portfolio Web Server
cd /d "%~dp0"
echo ========================================================
echo Starting Suman Garai Portfolio Server...
echo ========================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
pause
