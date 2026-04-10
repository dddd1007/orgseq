@echo off
REM Quick-launch: connect to running Emacs server, or start a new instance.
REM
REM Requires runemacs.exe (or emacs.exe) to be on PATH. The org-seq config
REM also adds WinGet/Scoop bin paths to exec-path at startup, but ec.cmd
REM runs before Emacs, so PATH must already include your Emacs install.
REM
REM Common Emacs install locations to add to PATH manually if needed:
REM   MSYS2 UCRT64:  C:\msys64\ucrt64\bin
REM   MSYS2 mingw64: C:\msys64\mingw64\bin
REM   WinGet:        %LOCALAPPDATA%\Microsoft\WinGet\Links
REM   Scoop:         %USERPROFILE%\scoop\shims
REM
REM If runemacs.exe is in a non-standard path, edit the -a fallback below.
emacsclient.exe -c -a "runemacs.exe" %*
