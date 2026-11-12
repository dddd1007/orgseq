@echo off
rem orgseq --- command line and MCP server for the org-seq configuration.
rem See bin/orgseq for the environment variables; this is the Windows launcher.
setlocal
set "HERE=%~dp0"
if defined ORG_SEQ_EMACS_DIR (
  set "DIR=%ORG_SEQ_EMACS_DIR%"
) else if exist "%HERE%..\init.el" (
  for %%I in ("%HERE%..") do set "DIR=%%~fI"
) else (
  set "DIR=%USERPROFILE%\.emacs.d"
)
if not defined ORG_SEQ_EMACS set "ORG_SEQ_EMACS=emacs"
if not exist "%DIR%\lisp\orgseq-cli.el" (
  echo orgseq: no org-seq configuration in %DIR% ^(set ORG_SEQ_EMACS_DIR^) 1>&2
  exit /b 2
)
if defined ORG_SEQ_DEBUG (
  "%ORG_SEQ_EMACS%" --batch --init-directory "%DIR%" -l "%DIR%\init.el" -l "%DIR%\lisp\orgseq-cli.el" -f my/cli-main -- %*
) else (
  "%ORG_SEQ_EMACS%" --batch --init-directory "%DIR%" -l "%DIR%\init.el" -l "%DIR%\lisp\orgseq-cli.el" -f my/cli-main -- %* 2>nul
)
exit /b %ERRORLEVEL%
