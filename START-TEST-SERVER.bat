@echo off
title Society Gate - Test Server
rem Double-click this file to start a test server on this laptop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-test-server.ps1"
echo.
echo The server has stopped. Press any key to close this window.
pause >nul
