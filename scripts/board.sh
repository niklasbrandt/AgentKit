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
# Settings come from .factory.json at the repo root ( or $FACTORY_JSON ). "project" is required, the rest optional:
#   { "project": 1, "owner": "<GitHub handle; default: the repo's owner>", "reviewer": "<default: owner>", "repo": "owner/name",
#     "lang": "en" | "de"    ( preset for column names, labels and wording; see lang.sh; default en ),
#     "columns": { "epics": "Epics", "backlog": "Backlog", "ready": "Ready", "human": "In Progress (Human)",
#                  "agent": "In Progress (Agent)", "review": "In Review", "done": "Done" },
#     "labels": { "merged": "merged" }, "terms": { "mergedLine": "Merged" } }
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

sub=${1:-help}; [ $# -gt 0 ] && shift
case "$sub" in
	tidy) cmd_tidy ;;
	ids) cmd_ids "$@" ;;
	list) cmd_list "$@" ;;
	next) cmd_next ;;
	status) cmd_status "$@" ;;
	add) cmd_add "$@" ;;
	move) cmd_move "$@" ;;
	merged) cmd_merged "$@" ;;
	*) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; [ "$sub" = help ] || exit 2 ;;
esac
