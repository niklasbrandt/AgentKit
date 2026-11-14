#!/usr/bin/env bash
# Watchdog for headless browser work: runs a command, sends it TERM after a timeout, then kills every headless Chrome that was left
# orphaned ( puppeteer's profile directory, parent process 1 ).
#   run.sh <timeout s> <command> [args...]
#   run.sh 900 node "$CLAUDE_PLUGIN_ROOT/scripts/picdiff.mjs" before/ after/
# Also for a dev server in the background ( no guard needed ): FACTORY_LOAD_WAIT=0 run.sh 14400 npx vite --port 5226 --strictPort
# Guard before the start: while the 1-minute load average is above the core count, or the headless cap is reached, it waits ( one line on
# stderr ), at most FACTORY_LOAD_WAIT seconds ( default 600; 0 = no guard ), then runs anyway. Headless browsers share the GPU with the
# owner's browser. The cap is the recommended "headless" of capacity.sh ( measured: GPU, memory, browsers running ), re-measured while it
# waits; without capacity.sh or jq it is "headlessMax" ( alias "headlessCap", .factory.json, default 4 ). HEADLESS_CAP=<n> overrides both.
# The cap counts browsers of the testing build ( Chrome for Testing in a cache folder ), never the owner's installed browser bundle.
# Each guarded run appends its queue time to FACTORY_WAITLOG ( default /tmp/agentkit-runwaits.log ), read by capacity.sh ( contention ).
# FACTORY_CHROME_PATTERN overrides the pattern that identifies the Chromes ( default: puppeteer_dev_chrome_profile ).
if [ $# -lt 2 ]; then echo "usage: run.sh <timeout s> <command> [args...]" >&2; exit 2; fi
T=$1; shift
PATTERN=${FACTORY_CHROME_PATTERN:-puppeteer_dev_chrome_profile}
WAIT=${FACTORY_LOAD_WAIT:-600}

ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
HERE=$( cd "$( dirname "$0" )" && pwd )
CAP=4
[ -f "$CFG" ] && command -v jq >/dev/null && CAP=$( jq -r '.headlessMax // .headlessCap // 4' "$CFG" 2>/dev/null || echo 4 )
cap() { # the headless cap right now
	local c=""
	if [ -n "${HEADLESS_CAP:-}" ]; then echo "$HEADLESS_CAP"; return; fi
	[ -x "$HERE/capacity.sh" ] && command -v jq >/dev/null && c=$( FACTORY_JSON=$CFG "$HERE/capacity.sh" --json --no-disk 2>/dev/null | jq -r '.headless // empty' 2>/dev/null )
	echo "${c:-$CAP}"
}
CORES=$( sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 1 )
load1() { { sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg 2>/dev/null; } | tr -d '{}' | awk '{ print $1 }'; }
# one browser = one profile directory, however many helper processes it has
browsers() { ps -axo command 2>/dev/null | grep -o "${PATTERN}[^ ]*" | sort -u | wc -l | tr -d ' '; }
busy() { NOWCAP=$( cap ); [ "$( awk -v l="$( load1 )" -v c="$CORES" 'BEGIN { print ( l > c ) }' )" = 1 ] || [ "$( browsers )" -ge "$NOWCAP" ]; }
t0=$( date +%s )
if [ "$WAIT" -gt 0 ] && busy; then
	echo "run.sh: waiting ( load $( load1 ) / $CORES cores, $( browsers ) / $NOWCAP headless browsers ), at most ${WAIT}s" >&2
	end=$(( t0 + WAIT ))
	while busy && [ "$( date +%s )" -lt "$end" ]; do sleep 10; done
fi
# every guarded run logs how long it queued ( "<epoch> <seconds>" ): capacity.sh reads it to see whether more agents only add waiting
[ "$WAIT" -gt 0 ] && echo "$t0 $(( $( date +%s ) - t0 ))" >> "${FACTORY_WAITLOG:-/tmp/agentkit-runwaits.log}" 2>/dev/null

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
