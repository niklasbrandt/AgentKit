#!/usr/bin/env bash
# Serialises merge → verify → push across the builders on one machine: the command runs under one lock per repository, so a
# second builder waits ( free ) instead of merging, verifying and finding the branch moved under it ( a second verify ).
#   mergelock.sh <command...>           e.g. mergelock.sh bash -c 'git fetch origin && git merge origin/main && npm run verify && git push origin HEAD:main'
# The lock is $FACTORY_LOCK or /tmp/factory-<repo>.lock; MERGELOCK_WAIT ( seconds, default 3600 ) bounds the wait.
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: mergelock.sh <command...>" >&2; exit 2; }
ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
LOCK=${FACTORY_LOCK:-/tmp/factory-$( basename "$( git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT" )" | sed 's/[^A-Za-z0-9_-]/-/g' ).lock}
WAIT=${MERGELOCK_WAIT:-3600}
if command -v flock >/dev/null; then
	exec flock -w "$WAIT" "$LOCK" "$@"
fi
# macOS has no flock: mkdir is atomic
t=0
until mkdir "$LOCK.d" 2>/dev/null; do
	[ $t -lt "$WAIT" ] || { echo "mergelock: still locked after ${WAIT}s ( $LOCK.d )" >&2; exit 75; }
	sleep 5; t=$(( t + 5 ))
done
trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT INT TERM
"$@"
