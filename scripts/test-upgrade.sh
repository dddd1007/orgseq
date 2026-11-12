#!/usr/bin/env bash
# test-upgrade.sh --- Exercise `orgseq upgrade' end to end (Linux, macOS)
#
# Builds a bare "remote" cloned from this checkout's committed HEAD, a
# working clone and a scratch Emacs directory under one temporary
# directory, deploys, publishes new versions, and checks that
# `orgseq upgrade --check' and `orgseq upgrade' behave as documented via
# the URL path and the local-checkout path.  Nothing outside the temporary
# directory is read or written; uncommitted changes in this checkout are
# not part of the test.  Deployments use --skip-checks --skip-verify
# (no prerequisite checks, no byte-compile gate) to stay fast.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { # check DESCRIPTION CMD...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}
eq() { # eq DESCRIPTION EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

remote="$work/remote.git"
clone="$work/clone"
other="$work/other"
target="$work/emacs"
mkdir "$target"

git clone --quiet --bare "$ROOT" "$remote"
git clone --quiet "$remote" "$clone"
branch="$(git -C "$clone" symbolic-ref --short HEAD)"

bump() { # bump REPO VERSION : commit a new VERSION in REPO
  printf '%s\n' "$2" > "$1/VERSION"
  git -C "$1" add VERSION
  git -C "$1" commit --quiet -m "bump $2"
}
publish() { # publish VERSION : new version in the remote via another clone
  rm -rf "$other"
  git clone --quiet "$remote" "$other"
  bump "$other" "$1"
  git -C "$other" push --quiet origin "HEAD:$branch"
}
installed() { cat "$target/.org-seq-version"; }
orgseq() { "$target/bin/orgseq" "$@"; }
status_of() { # status_of CMD... : exit status without aborting
  local s=0; "$@" >/dev/null 2>&1 || s=$?; printf '%s' "$s"
}

echo "== Deploy"
bash "$clone/deploy.sh" --target "$target" --skip-checks --skip-verify --no-backup >/dev/null
base="$(tr -d '[:space:]' < "$clone/VERSION")"
short="$(git -C "$clone" rev-parse HEAD | cut -c1-7)"
eq "version file" "$base ($short)" "$(installed)"
eq "orgseq version" "$base ($short)" "$(orgseq version)"
eq "record path" "path=$clone" "$(grep '^path=' "$target/.org-seq-source")"
eq "record url" "url=$remote" "$(grep '^url=' "$target/.org-seq-source")"
eq "record ref" "ref=$branch" "$(grep '^ref=' "$target/.org-seq-source")"
eq "record commit" "commit=$(git -C "$clone" rev-parse HEAD)" "$(grep '^commit=' "$target/.org-seq-source")"
check "no source record in user/" test ! -e "$target/user/.org-seq-source"

echo "== Credentials are not recorded"
cred="$work/cred-clone"
cred_target="$work/emacs-cred"
mkdir "$cred_target"
git clone --quiet "$remote" "$cred"
git -C "$cred" remote set-url origin "https://someone:s3cret-token@example.invalid/org-seq.git"
bash "$cred/deploy.sh" --target "$cred_target" --skip-checks --skip-verify --no-backup >/dev/null
eq "credentials stripped" "url=https://example.invalid/org-seq.git" "$(grep '^url=' "$cred_target/.org-seq-source")"
check "no secret in record" test -z "$(grep -r 's3cret' "$cred_target/.org-seq-source" || true)"

echo "== User data"
mkdir -p "$target/notes" "$target/user"
printf '* mine\n' > "$target/notes/keep.org"
printf '(setq my-own t)\n' > "$target/user/config.el"
userdata() { (cd "$target" && find notes user -type f -exec sha256sum {} + | sort); }
before_user="$(userdata)"
clone_head="$(git -C "$clone" rev-parse HEAD)"

echo "== Up to date"
eq "check exits 0 when current" 0 "$(status_of "$target/bin/orgseq" upgrade --check)"

echo "== URL source"
publish 0.1.1
eq "check --from remote exits 10" 10 "$(status_of "$target/bin/orgseq" upgrade --check --from "$remote")"
eq "check leaves the install alone" "$base ($short)" "$(installed)"
eq "recorded checkout is used as it is (no pull)" 0 "$(status_of "$target/bin/orgseq" upgrade --check)"
out="$(orgseq upgrade --from "$remote" --skip-checks --skip-verify --no-backup 2>/dev/null)"
case "$(installed)" in "0.1.1 ("*) ok "upgrade via URL";; *) bad "upgrade via URL ($(installed))";; esac
case "$out" in *"-> 0.1.1 ("*) ok "prints old -> new";; *) bad "prints old -> new ($out)";; esac
check "source cache created" test -d "$target/.cache/source/.git"
eq "check after upgrade exits 0" 0 "$(status_of "$target/bin/orgseq" upgrade --check --from "$remote")"

echo "== Recorded path gone: falls back to the recorded URL"
publish 0.1.2
sed -i "s|^path=.*|path=$work/does-not-exist|" "$target/.org-seq-source"
eq "check via recorded url exits 10" 10 "$(status_of "$target/bin/orgseq" upgrade --check)"
orgseq upgrade --skip-checks --skip-verify --no-backup >/dev/null 2>&1
case "$(installed)" in "0.1.2 ("*) ok "upgrade via recorded url";; *) bad "upgrade via recorded url ($(installed))";; esac

echo "== Local checkout source"
git -C "$clone" pull --quiet origin "$branch"
bump "$clone" 0.2.0
echo "scratch" > "$clone/untracked.txt"
clone_head="$(git -C "$clone" rev-parse HEAD)"
clone_status="$(git -C "$clone" status --porcelain)"
eq "check --from clone exits 10" 10 "$(status_of "$target/bin/orgseq" upgrade --check --from "$clone")"
orgseq upgrade --from "$clone" --skip-checks --skip-verify --no-backup >/dev/null 2>&1
case "$(installed)" in "0.2.0 ("*) ok "upgrade via local checkout";; *) bad "upgrade via local checkout ($(installed))";; esac
eq "record path is the checkout" "path=$clone" "$(grep '^path=' "$target/.org-seq-source")"
eq "clone HEAD unchanged" "$clone_head" "$(git -C "$clone" rev-parse HEAD)"
eq "clone status unchanged" "$clone_status" "$(git -C "$clone" status --porcelain)"
check "untracked file kept" test -f "$clone/untracked.txt"
rm -f "$clone/untracked.txt"
bump "$clone" 0.2.1
eq "recorded path used by default" 10 "$(status_of "$target/bin/orgseq" upgrade --check)"
orgseq upgrade --skip-checks --skip-verify --no-backup >/dev/null 2>&1
case "$(installed)" in "0.2.1 ("*) ok "upgrade via recorded path";; *) bad "upgrade via recorded path ($(installed))";; esac

echo "== Refusals"
fake="$work/fake"
mkdir -p "$fake/bin"
cp "$target/bin/orgseq" "$fake/bin/orgseq"
: > "$fake/init.el"
eq "no usable source exits 2" 2 "$(status_of "$fake/bin/orgseq" upgrade --check)"
eq "unknown option exits 2" 2 "$(status_of "$target/bin/orgseq" upgrade --bogus)"
nodeploy="$work/nodeploy"
git init --quiet "$nodeploy"
git -C "$nodeploy" commit --quiet --allow-empty -m empty
eq "source without deploy.sh exits 2" 2 "$(status_of "$target/bin/orgseq" upgrade --check --from "$nodeploy")"

echo "== User data untouched"
eq "notes/ and user/ unchanged" "$before_user" "$(userdata)"

if [ "$failures" -ne 0 ]; then
  echo "== $failures upgrade check(s) failed"
  exit 1
fi
echo "== Upgrade checks passed"
