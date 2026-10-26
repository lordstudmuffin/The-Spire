@echo off
rem The Spire: start a dedicated floor server on this PC (auto-restarts).
rem Double-click, or pass options through, e.g.:
rem   run_server.bat -Port 4434 -Name "Test Realm II" -DataDir "%LOCALAPPDATA%\TheSpireServer2"
rem See docs\DEDICATED_SERVER.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_server.ps1" %*
if errorlevel 1 pause
