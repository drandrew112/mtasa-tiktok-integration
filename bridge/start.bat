@echo off
REM Runs the TikTok bridge and restarts it if it ever exits.
cd /d "%~dp0"

:loop
echo [start.bat] launching bridge...
node index.js
echo [start.bat] bridge exited (code %ERRORLEVEL%), restarting in 5s...
timeout /t 5 /nobreak >nul
goto loop
