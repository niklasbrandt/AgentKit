#!/usr/bin/env bash
# Helper for the kanban board ( GitHub Projects v2 ) of the repo you run it in.
#   board.sh ids <project> <owner>        print the project id, the Status field id and the option ids ( read-only )
#   board.sh list [column]                cards with column, issue number and title ( read-only )
#   board.sh next                         the top card of Ready, else of Backlog ( read-only )
#   board.sh status <issue>               column, assignees and labels of an issue ( read-only )
#   board.sh add <issue-url> "<column>"   put an issue on the board in a column
#   board.sh move <issue> "<column>"      move a card; to In Review it also assigns the ticket's author, out of it removes that assignee
#   board.sh merged <issue> <sha> <branch>   add the line "**Merged:** <sha> in <branch>", the label and the author as assignee
#   board.sh tidy                         take cards without a column off the board when their issue is a sub-issue of a package ( GitHub's auto-add puts them back )
#   board.sh state [--json]               a draft of STATE.md from the board: running, queue, owner's cards, last hand-backs, cards without a column ( read-only )
#   board.sh stale [--minutes N] [--json]   per git worktree: minutes since the last commit and the last file change, running processes, verdict STALE ( default N = 45 ); the merge lock and its age ( read-only )
# Settings come from .factory.json at the repo root ( or $FACTORY_JSON ). "project" is required, the rest optional:
#   { "project": 1, "owner": "<GitHub handle; default: the repo's owner>", "reviewer": "<default: owner>", "repo": "owner/name",
#     "lang": "en" | "de"    ( preset for column names, labels and wording; see lang.sh; default en ),
#     "columns": { "epics": "Epics", "backlog": "Backlog", "ready": "Ready", "human": "In Progress (Human)",
#                  "agent": "In Progress (Agent)", "review": "In Review", "done": "Done" },
#     "labels": { "merged": "merged" }, "terms": { "mergedLine": "Merged" },
#     "headlessCap": 3       ( concurrent headless browsers on this machine; shown under Limits by state, enforced by run.sh ) }
# Guards: agents never move a card to Done and never touch a card that already is in Done ( set FACTORY_OWNER=1 to lift this, for the owner ).
set -euo pipefail

command -v gh >/dev/null || { echo "board.sh: gh is not installed" >&2; exit 2; }
command -v jq >/dev/null || { echo "board.sh: jq is not installed" >&2; exit 2; }

ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
cfg() { # cfg <jq path> <default>
	local v=""
	[ -f "$CFG" ] && v=$( jq -r "$1 // empty" "$CFG" 2>/dev/null || true )
	echo "${v:-$2}"
}
# shellcheck source=lang.sh
. "$( cd "$( dirname "$0" )" && pwd )/lang.sh"

REPO=$( cfg .repo "" )
repo() { [ -n "$REPO" ] && echo "$REPO" || gh repo view --json nameWithOwner --jq .nameWithOwner; }

PROJECT=$( cfg .project "" )
OWNER=$( cfg .owner "" )
[ -n "$OWNER" ] || { OWNER=$( repo ); OWNER=${OWNER%%/*}; }
REVIEWER=$( cfg .reviewer "$OWNER" )
C_EPICS=$( cfg .columns.epics "$D_EPICS" )
C_BACKLOG=$( cfg .columns.backlog "$D_BACKLOG" )
C_READY=$( cfg .columns.ready "$D_READY" )
C_HUMAN=$( cfg .columns.human "$D_HUMAN" )
C_AGENT=$( cfg .columns.agent "$D_AGENT" )
C_REVIEW=$( cfg .columns.review "$D_REVIEW" )
C_DONE=$( cfg .columns.done "$D_DONE" )
L_MERGED=$( cfg .labels.merged "$D_L_MERGED" )
T_MERGED=$( cfg .terms.mergedLine "$D_T_MERGED" )
need_project() { [ -n "$PROJECT" ] || { echo "board.sh: \"project\" is not set in $CFG ( gh project list --owner $OWNER shows the numbers )" >&2; exit 2; }; }

# the board's JSON, once per call
items() { need_project; gh project item-list "$PROJECT" --owner "$OWNER" --format json --limit 300; }

# item_of <issue number>: the card's item id and column, tab separated
item_of() {
	local r; r=$( repo )
	items | jq -r --argjson n "$1" --arg r "$r" '.items[] | select(.content.number == $n and (.content.repository // $r) == $r) | [ .id, ( .status // "" ) ] | @tsv' | head -1
}

fields() { need_project; gh project field-list "$PROJECT" --owner "$OWNER" --format json; }

cmd_ids() {
	local p=${1:-$PROJECT} o=${2:-$OWNER}
	[ -n "$p" ] || { echo 'usage: board.sh ids <project> <owner>  ( or set "project" in .factory.json )' >&2; exit 2; }
	local pid f
	pid=$( gh project view "$p" --owner "$o" --format json --jq .id )
	f=$( gh project field-list "$p" --owner "$o" --format json )
	echo "project  $pid"
	echo "$f" | jq -r '.fields[] | select(.name == "Status") | "status   \(.id)", ( .options[] | "option   \(.id)  \(.name)" )'
	# the columns the workflow expects
	local missing=0 name
	for name in "$C_EPICS" "$C_BACKLOG" "$C_READY" "$C_HUMAN" "$C_AGENT" "$C_REVIEW" "$C_DONE"; do
		if ! echo "$f" | jq -e --arg n "$name" '.fields[] | select(.name == "Status") | .options[] | select(.name == $n)' >/dev/null; then
			echo "MISSING  column \"$name\" is not an option of the Status field" >&2; missing=1
		fi
	done
	return $missing
}

cmd_list() {
	items | jq -r --arg c "${1:-}" '.items[] | select($c == "" or .status == $c) | [ ( .status // "-" ), "#\( .content.number // "-" )", ( .title // .content.title // "" ) ] | @tsv'
}

cmd_next() {
	local col n
	for col in "$C_READY" "$C_BACKLOG"; do
		n=$( items | jq -r --arg c "$col" '[ .items[] | select(.status == $c and .content.type == "Issue") ][0] | if . then "#\(.content.number)\t\(.title)" else empty end' )
		if [ -n "$n" ]; then printf '%s\t%s\n' "$col" "$n"; return 0; fi
	done
	echo "nothing in $C_READY or $C_BACKLOG" >&2; return 1
}

cmd_status() {
	local r it
	r=$( repo ); it=$( item_of "$1" )
	echo "column    ${it#*$'\t'}"
	gh issue view "$1" --repo "$r" --json author,assignees,labels,state --jq '"author    \(.author.login)\nassignees \([.assignees[].login] | join(","))\nlabels    \([.labels[].name] | join(","))\nstate     \(.state)"'
}

set_status() { # set_status <item id> <column>
	local f pid fid oid
	f=$( fields )
	pid=$( gh project view "$PROJECT" --owner "$OWNER" --format json --jq .id )
	fid=$( echo "$f" | jq -r '.fields[] | select(.name == "Status") | .id' )
	oid=$( echo "$f" | jq -r --arg n "$2" '.fields[] | select(.name == "Status") | .options[] | select(.name == $n) | .id' )
	[ -n "$oid" ] || { echo "board.sh: no column \"$2\" on the board" >&2; exit 1; }
	gh project item-edit --id "$1" --project-id "$pid" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
}

cmd_add() {
	[ $# -eq 2 ] || { echo 'usage: board.sh add <issue-url> "<column>"' >&2; exit 2; }
	if [ "$2" = "$C_DONE" ] && [ -z "${FACTORY_OWNER:-}" ]; then echo "board.sh: agents never set $C_DONE" >&2; exit 1; fi
	local id
	id=$( gh project item-add "$PROJECT" --owner "$OWNER" --url "$1" --format json --jq .id )
	set_status "$id" "$2"
	echo "added $1 -> $2"
}

cmd_move() {
	[ $# -eq 2 ] || { echo 'usage: board.sh move <issue> "<column>"' >&2; exit 2; }
	local n=$1 to=$2 r it id from
	r=$( repo ); it=$( item_of "$n" )
	[ -n "$it" ] || { echo "board.sh: #$n is not on project $PROJECT" >&2; exit 1; }
	id=${it%%$'\t'*}; from=${it#*$'\t'}
	if [ -z "${FACTORY_OWNER:-}" ]; then
		[ "$from" != "$C_DONE" ] || { echo "board.sh: #$n is in $C_DONE; agents never touch it" >&2; exit 1; }
		[ "$to" != "$C_DONE" ] || { echo "board.sh: agents never set $C_DONE" >&2; exit 1; }
	fi
	[ "$from" != "$to" ] || { echo "#$n is already in $to"; return 0; }
	set_status "$id" "$to"
	local author
	if [ "$to" = "$C_REVIEW" ]; then
		author=$( gh issue view "$n" --repo "$r" --json author --jq .author.login )
		[ "${author%%\[*}" = "$author" ] || author=$REVIEWER   # a bot authored it: the reviewer
		gh issue edit "$n" --repo "$r" --add-assignee "$author" >/dev/null
	elif [ "$from" = "$C_REVIEW" ]; then
		gh issue edit "$n" --repo "$r" --remove-assignee "$REVIEWER" >/dev/null 2>&1 || true
		author=$( gh issue view "$n" --repo "$r" --json author --jq .author.login )
		gh issue edit "$n" --repo "$r" --remove-assignee "$author" >/dev/null 2>&1 || true
	fi
	echo "#$n: $from -> $to"
}

cmd_merged() {
	[ $# -eq 3 ] || { echo 'usage: board.sh merged <issue> <sha> <branch>' >&2; exit 2; }
	local n=$1 sha=$2 br=$3 r tmp author
	r=$( repo )
	gh label create "$L_MERGED" --repo "$r" --color 0E8A16 --description "Agent merged the branch, waiting for the owner's review" >/dev/null 2>&1 || true
	tmp=$( mktemp )
	# drop an earlier merged line ( either language ), then append the new one
	gh issue view "$n" --repo "$r" --json body --jq .body | grep -v -E '^\*\*(Gemergt|Merged):\*\*' > "$tmp" || true
	printf '\n**%s:** %s in %s\n' "$T_MERGED" "$sha" "$br" >> "$tmp"
	gh issue edit "$n" --repo "$r" --body-file "$tmp" --add-label "$L_MERGED" >/dev/null
	rm -f "$tmp"
	author=$( gh issue view "$n" --repo "$r" --json author --jq .author.login )
	[ "${author%%\[*}" = "$author" ] || author=$REVIEWER
	gh issue edit "$n" --repo "$r" --add-assignee "$author" >/dev/null
	echo "#$n: $T_MERGED $sha in $br, label $L_MERGED, assignee $author"
}

cmd_tidy() {
	local r; r=$( repo )
	items | jq -r '.items[] | select( ( .status // "" ) == "" and .content.type == "Issue" ) | [ .id, .content.number ] | @tsv' | while IFS=$'\t' read -r id n; do
		if [ "$( gh api "repos/$r/issues/$n/parent" --jq .number 2>/dev/null )" != "" ]; then
			gh project item-delete "$PROJECT" --owner "$OWNER" --id "$id" >/dev/null && echo "#$n off the board ( sub-issue )"
		fi
	done
}

# state [--json]: the parts of STATE.md the board knows; agents, ports and worktrees are the orchestrator's to fill in.
# Calls: one gh project item-list ( GraphQL ), one gh api for the newest 30 issues with the merged label ( REST: body and date ).
# If the GraphQL call fails ( rate limit ), the REST part is still printed.
cmd_state() {
	local json=0; [ "${1:-}" = "--json" ] && json=1
	local r all merged cap load cores now
	r=$( repo )
	all=$( items 2>/dev/null ) || all=""
	merged=$( gh api "repos/$r/issues?labels=$( jq -rn --arg l "$L_MERGED" '$l | @uri' )&state=all&sort=updated&direction=desc&per_page=30" 2>/dev/null \
		| jq --arg tm "**$T_MERGED:**" '[ .[] | { number, title, date: .updated_at[0:10],
			line: ( [ ( .body // "" ) | split("\n")[] | select( startswith($tm) ) ] | last // "" ) } ]' 2>/dev/null ) || merged='[]'
	[ -n "$merged" ] || merged='[]'
	cap=$( cfg .headlessCap 3 )
	cores=$( sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo "?" )
	load=$( { sysctl -n vm.loadavg 2>/dev/null || cat /proc/loadavg 2>/dev/null; } | tr -d '{}' | awk '{ print $1 }' )
	now=$( date '+%Y-%m-%d %H:%M' )
	printf '%s' "${all:-null}" | jq -r --argjson json "$json" --argjson merged "$merged" --arg agent "$C_AGENT" --arg review "$C_REVIEW" \
		--arg ready "$C_READY" --arg backlog "$C_BACKLOG" --arg human "$C_HUMAN" --arg lm "$L_MERGED" --arg tm "$T_MERGED" \
		--arg cap "$cap" --arg load "${load:-?}" --arg cores "$cores" --arg now "$now" '
		( if type == "object" and has("items") then . else null end ) as $b
		| def cards($c): if $b == null then null else [ $b.items[] | select( ( .status // "" ) == $c and .content.type == "Issue" ) | { number: .content.number, title: ( .title // .content.title ), labels: ( .labels // [] ) } ] end;
		def row: "#\(.number) \(.title)";
		( if $b == null then null else [ $b.items[] | select( .content.type == "Issue" and .status == $review and ( ( .labels // [] ) | index($lm) ) ) | .content.number ] end ) as $rev
		| ( if $b == null then [] else [ $b.items[] | .content.number ] end ) as $onboard
		| { at: $now, board: ( $b != null ),
			running: cards($agent), human: cards($human),
			ready: ( cards($ready) | if . then .[0:10] else . end ), backlog: ( cards($backlog) | if . then .[0:5] else . end ),
			readyCount: ( cards($ready) | if . then length else null end ), backlogCount: ( cards($backlog) | if . then length else null end ),
			handbacks: [ $merged[] | select( $rev == null or ( .number as $n | ( $rev | index($n) ) or ( $onboard | index($n) | not ) ) ) | . + { sha: ( .line | ( capture("\\*\\* *`?(?<s>[0-9a-f]{7,40})") | .s ) // "" ),
				entry: ( .line | ( capture("(?<e>index[-.][A-Za-z0-9_-]+\\.js)") | .e ) // "?" ),
				branch: ( .line | ( capture(" in (?<b>[^ ]+)") | .b ) // "" ) } ],
			reviewMerged: ( if $rev then ( $rev | length ) else null end ),
			noColumn: ( if $b == null then null else [ $b.items[] | select( ( .status // "" ) == "" and .content.type == "Issue" ) | { number: .content.number, title: ( .title // .content.title ) } ] end ),
			limits: { headlessCap: ( $cap | tonumber? // $cap ), load1: $load, cores: $cores } }
		| if $json == 1 then . else
		[ "# STATE ( draft from the board, \(.at) )", "",
		  ( if .board then empty else "> The board ( GraphQL ) could not be read, probably rate-limited: only the REST part below. Retry in a few minutes.\n" end ),
		  "## Running", "", "Shift lead: <agent / none>", "",
		  "| Ticket | Title | Agent / model | Worktree | Ports | Started | Last progress | Phase |", "|---|---|---|---|---|---|---|---|",
		  ( .running // [] | .[] | "| #\(.number) | \(.title) | ? | ? | ? | ? | ? | build / finish / fix |" ), "",
		  "## Waiting", "", "- <ticket> → <waits for what>", "",
		  "## Queue", "",
		  ( if .ready == null then "- ?" else ( ( .ready | to_entries[] | "\(.key + 1). \(.value | row) ( \($ready) )" ),
		    ( if .readyCount > 10 then "   … \(.readyCount - 10) more in \($ready)" else empty end ),
		    ( .backlog | to_entries[] | "- \(.value | row) ( \($backlog) )" ),
		    ( if .backlogCount > 5 then "   … \(.backlogCount - 5) more in \($backlog)" else empty end ) ) end ), "",
		  "## Owner decisions open", "",
		  ( .human // [] | .[] | "- \(row) ( \($human) )" ), "- <decision> — recommendation: <…>", "",
		  "## Limits", "",
		  "- Builders: <cap> at once", "- Headless browsers: \(.limits.headlessCap) at once, machine-wide; load guard: 1-min load \(.limits.load1) / \(.limits.cores) cores",
		  "- Ports: <ticket → port>", "- Locked files: <file → ticket>", "- Owner'"'"'s ports, never touched: <…>", "",
		  "## Last hand-backs", "",
		  "| Ticket | Title | Sha | Branch | Deployed entry | Date |", "|---|---|---|---|---|---|",
		  ( .handbacks[0:10][] | "| #\(.number) | \(.title) | \(.sha) | \(.branch) | \(.entry) | \(.date) |" ),
		  ( if ( .reviewMerged // 0 ) > 10 then "", "\(.reviewMerged) cards in \($review) carry `\($lm)`; the 10 updated last are shown ( sub-issues off the board included )." else empty end ), "",
		  "## Notes", "",
		  ( if ( .noColumn // [] | length ) > 0 then "- Cards without a column ( `board.sh tidy` takes sub-issues off ): \( [ .noColumn[] | row ] | join("; ") )" else empty end ),
		  "- <date>: <self-set rule or incident>"
		] | .[] end'
}

# stale [--minutes N] [--json]: the watchdog's eyes. For every worktree of this repository: last commit, last change of any file
# ( node_modules, dist, .git excluded ), whether a process runs inside it ( ps, not lsof +D ), verdict STALE when both ages exceed N and no process runs.
# Needs no board access ( no gh call ). A merge lock older than 30 minutes with no mergelock.sh process is reported as stale.
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
newest_change() { # newest_change <dir>: epoch seconds of the newest file, empty if none
	find "$1" \( -name node_modules -o -name dist -o -name .git \) -prune -o -type f -print0 2>/dev/null \
		| xargs -0 stat -f %m 2>/dev/null | sort -n | tail -1 || true
}
cmd_stale() {
	local mins=45 json=0
	while [ $# -gt 0 ]; do case "$1" in
		--minutes) mins=${2:?--minutes needs a number}; shift ;; --json) json=1 ;;
		*) echo 'usage: board.sh stale [--minutes N] [--json]' >&2; exit 2 ;; esac; shift; done
	case "$mins" in ''|*[!0-9]*) echo "board.sh: --minutes needs a whole number" >&2; exit 2 ;; esac
	local now ps_out rows="" path branch c f cm fm procs verdict
	now=$( date +%s ); ps_out=$( ps -axo pid,command 2>/dev/null || true )
	while IFS= read -r path; do
		[ -d "$path" ] || continue
		branch=$( git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)" )
		c=$( git -C "$path" log -1 --format=%ct 2>/dev/null || echo 0 ); c=${c:-0}
		f=$( newest_change "$path" ); f=${f:-0}; [ "$f" -ge "$c" ] || f=$c
		cm=$(( ( now - c ) / 60 )); fm=$(( ( now - f ) / 60 ))
		procs=$( printf '%s\n' "$ps_out" | P="$path" SELF="$$ $PPID" awk '
			BEGIN { n = split( ENVIRON["SELF"], s, " " ) }
			{ for ( i = 1; i <= n; i++ ) if ( $1 == s[i] ) next
			  cmd = $0; sub( /^ *[0-9]+ +/, "", cmd ); p = ENVIRON["P"]; i = index( cmd, p )
			  if ( i == 0 ) next
			  nx = substr( cmd, i + length( p ), 1 ); if ( nx == "" || nx == "/" || nx == " " || nx == "\"" ) k++ }
			END { print k + 0 }' )
		verdict=ok; [ "$cm" -gt "$mins" ] && [ "$fm" -gt "$mins" ] && [ "$procs" -eq 0 ] && verdict=STALE
		rows+="$path"$'\t'"$branch"$'\t'"$cm"$'\t'"$fm"$'\t'"$procs"$'\t'"$verdict"$'\n'
	done < <( git worktree list --porcelain 2>/dev/null | awk '/^worktree /{ sub( /^worktree /, "" ); p = $0 } /^bare/{ p = "" } /^$/ { if ( p != "" ) print p; p = "" } END { if ( p != "" ) print p }' )
	# the merge lock of mergelock.sh ( same key )
	local common lock="" lage="" lstate="none" holders base
	common=$( git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir 2>/dev/null || pwd )
	base=${FACTORY_LOCK:-/tmp/factory-$( printf '%s' "$common" | sed 's/[^A-Za-z0-9_-]/-/g' ).lock}
	if [ -d "$base.d" ]; then lock="$base.d"; elif [ -e "$base" ]; then lock="$base"; fi
	if [ -n "$lock" ]; then
		lage=$(( ( now - $( mtime "$lock" ) ) / 60 ))
		holders=$( printf '%s\n' "$ps_out" | grep -c '[m]ergelock\.sh' || true )
		if [ -d "$base.d" ]; then
			if [ "$lage" -gt 30 ] && [ "${holders:-0}" -eq 0 ]; then lstate="STALE LOCK ( older than 30 min, no mergelock.sh process: remove it with rmdir )"; else lstate="held"; fi
		else lstate="flock file ( only held while a process runs under it; harmless )"; fi
	fi
	if [ "$json" -eq 1 ]; then
		printf '%s' "$rows" | jq -R -s --argjson m "$mins" --arg lock "$lock" --arg lage "$lage" --arg ls "$lstate" '
			{ minutes: $m, worktrees: [ split("\n")[] | select(length > 0) | split("\t") | { path: .[0], branch: .[1], lastCommitMin: (.[2] | tonumber), lastChangeMin: (.[3] | tonumber), processes: (.[4] | tonumber), verdict: .[5] } ],
			  mergelock: ( if $lock == "" then null else { path: $lock, ageMin: ( $lage | tonumber ), state: $ls } end ) }'
	else
		echo "# Worktrees ( STALE: no commit and no file change for more than $mins min, no process inside )"; echo
		echo "| Worktree | Branch | Last commit ( min ) | Last change ( min ) | Processes | Verdict |"; echo "|---|---|---|---|---|---|"
		printf '%s' "$rows" | awk -F'\t' 'NF { printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6 }'
		echo
		if [ -n "$lock" ]; then echo "Merge lock: $lock, $lage min old, $lstate"; else echo "Merge lock: none"; fi
	fi
}

sub=${1:-help}; [ $# -gt 0 ] && shift
case "$sub" in
	tidy) cmd_tidy ;;
	stale) cmd_stale "$@" ;;
	state) cmd_state "$@" ;;
	ids) cmd_ids "$@" ;;
	list) cmd_list "$@" ;;
	next) cmd_next ;;
	status) cmd_status "$@" ;;
	add) cmd_add "$@" ;;
	move) cmd_move "$@" ;;
	merged) cmd_merged "$@" ;;
	*) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; [ "$sub" = help ] || exit 2 ;;
esac
