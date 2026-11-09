#!/usr/bin/env bash
# Measures the machine's bottlenecks and recommends how many agents and headless browsers may run right now ( read-only, no sudo ).
#   capacity.sh [--json] [--no-disk]
# Measures: the owner ( idle time since the last keyboard / mouse input, the owner's own ports in use ), CPU ( 1-minute load against the core count, thermal limit ), memory ( pressure level, free percentage, swap ), GPU ( utilisation,
# headless browsers of the testing build already running ), disk ( MB/s and tps over one second; --no-disk skips that second ).
# macOS first; Linux through /proc and nvidia-smi where present. A measure that cannot be read is shown as "?" and changes nothing.
# Owner: "active" while the last input is less than "idleMinutes" ( .factory.json, default 10 ) ago or one of "ownerPorts" ( e.g.
# [ 5217, 5210 ]: the owner's dev servers ) has an established connection; "idle Nm" from then on; "afk" from "afkMinutes" ( default 30 ) on. macOS: HIDIdleTime of
# IOHIDSystem; Linux: xprintidle if present, else idle counts as 0 ( active ).
# Recommendation: start at the maxima of .factory.json ( "agentsMax", default 6; "headlessMax", default 4, "headlessCap" read as its alias );
# afk: agentsMax + 2 when the load is at most 0.8 x cores and the GPU at most 70 %, so the factory runs flat out while nobody uses the machine.
# Then reduce:
#   owner active                agents -2, headless -2, and the GPU threshold below is 60 % instead of 70 %  ( idle / afk: no reservation )
#   load > 0.8 x cores          agents -1 per started 0.3 x cores above that
#   memory warn                 agents -2;  critical: agents 1 and headless 1
#   GPU utilisation > 70 %      headless -1 ( > 60 % while the owner is active );  > 90 %: headless 1
#   thermal limit < 100 %       agents -1
#   disk MB/s > "diskMBs"       agents -1   ( .factory.json, default 1500, an NVMe drive under heavy use )
# Never below 1 agent and 1 headless browser. free_headless = headless minus the headless browsers already running ( never below 0 ).
# --json: { agents, headless, free_headless, reasons, owner: "active" | "idle Nm" | "afk", measures: { … }, caps: { … } }. Always exits 0.
# FACTORY_JSON overrides the config path.
JSON=0; DISK=1
for a in "$@"; do case "$a" in --json) JSON=1 ;; --no-disk) DISK=0 ;; *) echo "usage: capacity.sh [--json] [--no-disk]" >&2; exit 0 ;; esac; done

ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
cfg() { # cfg <jq expr> <default>
	local v=""
	[ -f "$CFG" ] && command -v jq >/dev/null && v=$( jq -r "$1 // empty" "$CFG" 2>/dev/null || true )
	echo "${v:-$2}"
}
AMAX=$( cfg .agentsMax 6 ); HMAX=$( cfg '.headlessMax // .headlessCap' 4 ); DTH=$( cfg .diskMBs 1500 )
OS=$( uname -s )
num() { awk -v x="$1" 'BEGIN { exit !( x ~ /^[0-9]+(\.[0-9]+)?$/ ) }'; }

# owner: seconds since the last input, the owner's ports with an established connection
IDLE=""
if [ "$OS" = Darwin ]; then IDLE=$( ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ { printf "%d", $NF / 1000000000; exit }' )
elif command -v xprintidle >/dev/null; then IDLE=$( xprintidle 2>/dev/null | awk '{ printf "%d", $1 / 1000 }' ); fi
IDLE=${IDLE:-0}
OPORTS=$( cfg '.ownerPorts // [] | map( tostring ) | join(" ")' "" ); BUSYP=""
for p in $OPORTS; do
	if command -v lsof >/dev/null; then n=$( lsof -nP -iTCP:"$p" -sTCP:ESTABLISHED 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' )
	elif command -v ss >/dev/null; then n=$( ss -Htn state established "( sport = :$p )" 2>/dev/null | wc -l | tr -d ' ' )
	else n=0; fi
	[ "${n:-0}" -gt 0 ] && BUSYP="$BUSYP${BUSYP:+ }$p"
done
IMIN=$( cfg .idleMinutes 10 ); AMIN=$( cfg .afkMinutes 30 )
if [ -n "$BUSYP" ] || [ "$IDLE" -lt $(( IMIN * 60 )) ]; then OWNER=active; elif [ "$IDLE" -lt $(( AMIN * 60 )) ]; then OWNER="idle $(( IDLE / 60 ))m"; else OWNER=afk; fi

# CPU
CORES=$( sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "" )
LOAD=$( { sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg 2>/dev/null; } | tr -d '{}' | awk '{ print $1 }' )
THERM=""
if [ "$OS" = Darwin ]; then THERM=$( pmset -g therm 2>/dev/null | awk -F'= *' '/CPU_Speed_Limit/ { print $2 + 0; exit }' ); [ -n "$THERM" ] || THERM=100; fi

# memory: level normal / warn / critical, free percentage, swap used ( MB )
MEM=""; FREE=""; SWAP=""
if [ "$OS" = Darwin ]; then
	case "$( sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null )" in 1) MEM=normal ;; 2) MEM=warn ;; 4) MEM=critical ;; esac
	FREE=$( memory_pressure 2>/dev/null | awk -F': *' '/free percentage/ { gsub( /%/, "", $2 ); print $2 + 0 }' )
	if [ -z "$FREE" ]; then
		FREE=$( vm_stat 2>/dev/null | awk -v mem="$( sysctl -n hw.memsize 2>/dev/null )" '
			/page size of/ { ps = $8 } /Pages free/ { f = $3 } /Pages inactive/ { i = $3 } /Pages speculative/ { s = $3 }
			END { if ( mem > 0 && ps > 0 ) printf "%d", ( f + i + s ) * ps * 100 / mem }' )
	fi
	SWAP=$( sysctl -n vm.swapusage 2>/dev/null | awk '{ for ( i = 1; i <= NF; i++ ) if ( $i == "used" ) { v = $( i + 2 ); sub( /M$/, "", v ); printf "%d", v } }' )
elif [ -r /proc/meminfo ]; then
	read -r FREE SWAP < <( awk '/^MemTotal/ { t = $2 } /^MemAvailable/ { a = $2 } /^SwapTotal/ { st = $2 } /^SwapFree/ { sf = $2 }
		END { if ( t > 0 ) printf "%d %d\n", a * 100 / t, ( st - sf ) / 1024 }' /proc/meminfo )
fi
if [ -z "$MEM" ] && [ -n "$FREE" ]; then
	if [ "$FREE" -lt 10 ]; then MEM=critical; elif [ "$FREE" -lt 20 ]; then MEM=warn; else MEM=normal; fi
fi

# GPU: highest utilisation over all accelerators
GDEV=""; GREN=""
if [ "$OS" = Darwin ]; then
	GDEV=$( ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -o '"Device Utilization %"=[0-9]*' | awk -F= '$2 > m { m = $2 } END { if ( NR ) print m + 0 }' )
	GREN=$( ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -o '"Renderer Utilization %"=[0-9]*' | awk -F= '$2 > m { m = $2 } END { if ( NR ) print m + 0 }' )
elif command -v nvidia-smi >/dev/null; then
	GDEV=$( nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | awk '$1 > m { m = $1 } END { if ( NR ) print m + 0 }' )
fi
GPU=${GDEV:-$GREN}
# headless browsers of the testing build: main processes ( no --type= ) of a Chrome / Chromium started with --headless,
# not the owner's installed bundle under /Applications
BROWSERS=$( ps -axo command 2>/dev/null | grep -- '--headless' | grep -v -- '--type=' | grep -i 'chrom' | grep -v '^/Applications/' | grep -vc 'grep' )

# disk: one second, summed over all disks
DMBS=""; DTPS=""
if [ $DISK = 1 ]; then
	if [ "$OS" = Darwin ] && command -v iostat >/dev/null; then
		read -r DTPS DMBS < <( iostat -d -c 2 -w 1 2>/dev/null | tail -1 | awk '{ for ( i = 1; i + 2 <= NF; i += 3 ) { t += $( i + 1 ); m += $( i + 2 ) } printf "%d %.0f\n", t, m }' )
	elif [ -r /proc/diskstats ]; then
		snap() { awk '$3 ~ /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$/ { io += $4 + $8; s += $6 + $10 } END { print io + 0, s + 0 }' /proc/diskstats; }
		read -r i0 s0 < <( snap ); sleep 1; read -r i1 s1 < <( snap )
		DTPS=$(( i1 - i0 )); DMBS=$(( ( s1 - s0 ) * 512 / 1000000 ))
	fi
fi

# recommendation
AG=$AMAX; HL=$HMAX; R=(); GT=70
[ "$OWNER" = active ] && GT=60
if [ "$OWNER" = afk ] && num "$LOAD" && num "$CORES" && awk -v l="$LOAD" -v c="$CORES" 'BEGIN { exit !( l <= 0.8 * c ) }' && { ! num "$GPU" || [ "$GPU" -le 70 ]; }; then
	AG=$(( AMAX + 2 )); R+=( "owner afk, load and GPU low: agents $AMAX + 2" )
fi
if num "$LOAD" && num "$CORES"; then
	n=$( awk -v l="$LOAD" -v c="$CORES" 'BEGIN { o = l - 0.8 * c; if ( o <= 0 ) print 0; else { k = o / ( 0.3 * c ); print ( k == int( k ) ) ? k : int( k ) + 1 } }' )
	[ "$n" -gt 0 ] && { AG=$(( AG - n )); R+=( "load $LOAD > 0.8 x $CORES cores: agents -$n" ); }
fi
case "$MEM" in
	warn) AG=$(( AG - 2 )); R+=( "memory warn: agents -2" ) ;;
	critical) AG=1; HL=1; R+=( "memory critical: agents 1, headless 1" ) ;;
esac
if num "$GPU"; then
	if [ "$GPU" -gt 90 ]; then HL=1; R+=( "GPU $GPU % > 90: headless 1" )
	elif [ "$GPU" -gt "$GT" ]; then HL=$(( HL - 1 )); R+=( "GPU $GPU % > $GT: headless -1" ); fi
fi
if [ "$OWNER" = active ]; then
	AG=$(( AG - 2 )); HL=$(( HL - 2 ))
	R+=( "owner active ( input $(( IDLE / 60 )) min ago${BUSYP:+, ports $BUSYP in use} ): agents -2, headless -2" )
fi
num "$THERM" && [ "$THERM" -lt 100 ] && { AG=$(( AG - 1 )); R+=( "thermal limit $THERM %: agents -1" ); }
num "$DMBS" && [ "$DMBS" -gt "$DTH" ] && { AG=$(( AG - 1 )); R+=( "disk $DMBS MB/s > $DTH: agents -1" ); }
[ "$AG" -lt 1 ] && AG=1
[ "$HL" -lt 1 ] && HL=1
FH=$(( HL - BROWSERS )); [ "$FH" -lt 0 ] && FH=0
[ "$BROWSERS" -ge "$HL" ] && R+=( "$BROWSERS headless browsers already running: no free slot" )

jn() { if [ -n "$1" ]; then printf '%s' "$1"; else printf null; fi; }   # number or null
js() { if [ -n "$1" ]; then printf '"%s"' "$1"; else printf null; fi; } # string or null
if [ $JSON = 1 ]; then
	printf '{ "agents": %s, "headless": %s, "free_headless": %s, "reasons": [' "$AG" "$HL" "$FH"
	sep=""; for r in "${R[@]}"; do printf '%s"%s"' "$sep" "$r"; sep=", "; done
	printf ' ], "owner": "%s", "measures": { "owner_idle_s": %s, "owner_ports_busy": [%s],' "$OWNER" "$IDLE" "$( printf '%s' "$BUSYP" | sed 's/ /, /g' )"
	printf ' "cores": %s, "load1": %s, "thermal_limit": %s, "memory": %s, "memory_free_pct": %s, "swap_used_mb": %s,' \
		"$( jn "$CORES" )" "$( jn "$LOAD" )" "$( jn "$THERM" )" "$( js "$MEM" )" "$( jn "$FREE" )" "$( jn "$SWAP" )"
	printf ' "gpu_device_pct": %s, "gpu_renderer_pct": %s, "headless_running": %s, "disk_mbs": %s, "disk_tps": %s },' \
		"$( jn "$GDEV" )" "$( jn "$GREN" )" "$BROWSERS" "$( jn "$DMBS" )" "$( jn "$DTPS" )"
	printf ' "caps": { "agentsMax": %s, "headlessMax": %s, "diskMBs": %s, "idleMinutes": %s, "afkMinutes": %s }, "at": "%s" }\n' "$AMAX" "$HMAX" "$DTH" "$IMIN" "$AMIN" "$( date '+%Y-%m-%d %H:%M' )"
	exit 0
fi
q() { echo "${1:-?}"; }
RATIO=$( awk -v l="$LOAD" -v c="$CORES" 'BEGIN { if ( c > 0 && l != "" ) printf "%.2f", l / c; else print "?" }' )
CFGN=$CFG; [ -f "$CFG" ] || CFGN="no .factory.json, defaults"
echo "capacity  $( date '+%Y-%m-%d %H:%M' )  ( $( q "$CORES" ) cores; caps from $CFGN )"
printf '  %-10s %-42s %s\n' measure value threshold \
	cpu "load $( q "$LOAD" ) ( $RATIO x cores )" "> 0.8 x cores: agents -1 per 0.3 x cores over" \
	thermal "$( q "$THERM" ) % speed limit" "< 100: agents -1" \
	memory "$( q "$MEM" ), $( q "$FREE" ) % free, swap $( q "$SWAP" ) MB used" "warn: agents -2; critical: agents 1, headless 1" \
	gpu "device $( q "$GDEV" ) %, renderer $( q "$GREN" ) %" "> $GT: headless -1; > 90: headless 1" \
	browsers "$BROWSERS headless running" "running >= headless: no free slot" \
	disk "$( q "$DMBS" ) MB/s, $( q "$DTPS" ) tps" "> $DTH MB/s: agents -1" \
	caps "agentsMax $AMAX, headlessMax $HMAX" "" \
	owner "$OWNER ( input $(( IDLE / 60 )) min ago; ports ${BUSYP:-none} busy of ${OPORTS:-none} )" "active < $IMIN min: agents -2, headless -2, GPU 60 %; afk >= $AMIN min: agents +2"
for r in "${R[@]}"; do echo "  - $r"; done
echo "recommendation: agents $AG, headless $HL, free_headless $FH"
exit 0
