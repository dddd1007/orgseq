@echo off
rem ec.cmd — Quick Emacs client launcher
rem If a server is running, connects instantly (<0.1s).
rem If no server, starts a new Emacs instance as server (-a "").
rem
rem Usage:
rem   ec              — open a new frame
rem   ec file.org     — open file in a new frame
rem   ec -n file.org  — open file in existing frame (no new window)

emacsclient.exe -c -a "" %*
