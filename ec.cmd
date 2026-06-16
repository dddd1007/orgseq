@echo off
REM Quick-launch: connect to the org-seq Emacs server.
REM
REM The tray app (scripts\emacs-server-tray.ps1) starts the daemon with
REM --daemon=org-seq.  On Windows with server-use-tcp t, emacsclient must use
REM the full path to the named TCP auth file via -f.
REM
REM If Emacs is not on PATH, edit the paths below to match your install.
REM Common locations:
REM   Official:  C:\Program Files\Emacs\emacs-30.2\bin
REM   WinGet:    %LOCALAPPDATA%\Microsoft\WinGet\Links
REM   Scoop:     %USERPROFILE%\scoop\shims

REM Try PATH first, then fall back to the standard install location.
set "ORG_SEQ_DIR=%~dp0"
set "ORG_SEQ_SERVER_AUTH=%ORG_SEQ_DIR%server\org-seq"
if not exist "%ORG_SEQ_SERVER_AUTH%" if exist "%APPDATA%\.emacs.d\server\org-seq" set "ORG_SEQ_SERVER_AUTH=%APPDATA%\.emacs.d\server\org-seq"
if not exist "%ORG_SEQ_SERVER_AUTH%" set "ORG_SEQ_SERVER_AUTH=%USERPROFILE%\.emacs.d\server\org-seq"

where emacsclientw.exe >nul 2>&1
if %errorlevel% equ 0 (
    emacsclientw.exe -c -n -f "%ORG_SEQ_SERVER_AUTH%" %*
) else (
    "C:\Program Files\Emacs\emacs-30.2\bin\emacsclientw.exe" -c -n -f "%ORG_SEQ_SERVER_AUTH%" %*
)
