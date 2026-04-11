#!/usr/bin/env sh
# Quick-launch: connect to the org-seq Emacs server on Linux/macOS.
#
# Windows uses ec.cmd because the named TCP auth file needs a different
# emacsclient invocation there.

set -eu

SERVER_NAME="${ORG_SEQ_SERVER_NAME:-org-seq}"

find_emacs() {
  if command -v emacs >/dev/null 2>&1; then
    command -v emacs
    return 0
  fi

  if [ "$(uname -s)" = "Darwin" ] &&
     [ -x "/Applications/Emacs.app/Contents/MacOS/Emacs" ]; then
    printf '%s\n' "/Applications/Emacs.app/Contents/MacOS/Emacs"
    return 0
  fi

  return 1
}

find_emacsclient() {
  if command -v emacsclient >/dev/null 2>&1; then
    command -v emacsclient
    return 0
  fi

  if [ "$(uname -s)" = "Darwin" ] &&
     [ -x "/Applications/Emacs.app/Contents/MacOS/bin/emacsclient" ]; then
    printf '%s\n' "/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"
    return 0
  fi

  return 1
}

EMACS="$(find_emacs)" || {
  printf 'org-seq: emacs not found on PATH.\n' >&2
  exit 1
}

EMACSCLIENT="$(find_emacsclient)" || {
  printf 'org-seq: emacsclient not found on PATH.\n' >&2
  exit 1
}

if ! "$EMACSCLIENT" -s "$SERVER_NAME" -e t >/dev/null 2>&1; then
  "$EMACS" --daemon="$SERVER_NAME" >/dev/null 2>&1 &
  i=0
  while ! "$EMACSCLIENT" -s "$SERVER_NAME" -e t >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 80 ]; then
      printf 'org-seq: server "%s" did not become ready.\n' "$SERVER_NAME" >&2
      exit 1
    fi
    sleep 0.1
  done
fi

exec "$EMACSCLIENT" -c -n -s "$SERVER_NAME" "$@"
