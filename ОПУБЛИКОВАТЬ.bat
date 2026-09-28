@echo off
REM Publishes the local repository to GitHub.
REM ASCII-only on purpose: .cmd files with non-ASCII text break unpredictably.
REM No secrets in any of this. Git Credential Manager asks you directly.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1"
set RC=%ERRORLEVEL%
echo.
if not "%RC%"=="0" (
  echo ==========================================================
  echo   FAILED. Scroll up, read the message, send it to me.
  echo ==========================================================
) else (
  echo ==========================================================
  echo   DONE. Read the last screen for your repository URL.
  echo ==========================================================
)
pause
