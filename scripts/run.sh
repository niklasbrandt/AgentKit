#!/usr/bin/env bash
# Watchdog for headless browser work: runs a command, sends it TERM after a timeout, then kills every headless Chrome that was left
# orphaned ( puppeteer's profile directory, parent process 1 ).
#   run.sh <timeout s> <command> [args...]
#   run.sh 900 node "$CLAUDE_PLUGIN_ROOT/scripts/picdiff.mjs" before/ after/
# Also for a dev server in the background: run.sh 14400 npx vite --port 5226 --strictPort
# FACTORY_CHROME_PATTERN overrides the pattern that identifies the Chromes ( default: puppeteer_dev_chrome_profile ).
if [ $# -lt 2 ]; then echo "usage: run.sh <timeout s> <command> [args...]" >&2; exit 2; fi
T=$1; shift
PATTERN=${FACTORY_CHROME_PATTERN:-puppeteer_dev_chrome_profile}
"$@" &
P=$!
# the sleeper's output goes nowhere: a pipe after run.sh would otherwise wait for it to end
( sleep "$T" && kill -TERM "$P" ) >/dev/null 2>&1 &
W=$!
wait "$P"; RC=$?
pkill -P "$W" 2>/dev/null; kill "$W" 2>/dev/null
for c in $( pgrep -f "$PATTERN" ); do
	[ "$( ps -o ppid= -p "$c" | tr -d ' ' )" = "1" ] && kill -9 "$c" 2>/dev/null
done
exit $RC
