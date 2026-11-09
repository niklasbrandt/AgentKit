#!/usr/bin/env bash
# The board itself: create the GitHub project named after the repository and link it, and give its Status field the columns of the
# language preset. init.sh calls both when no project number is given; both can be run alone.
#   project.sh create [--owner <handle>] [--repo owner/name] [--title "<title>"]   finds or creates the board; prints the project number
#     order: the project linked to the repository ( several: exit 3, pass --project ); else the owner's project titled like the repo
#     ( linked then ); else a new one named after the repo. Other projects of the owner are listed so an existing board can be chosen.
#   project.sh columns <project> <owner> [--force]                                 adds the preset's missing columns to the Status field
# Columns: an empty board ( no items ) gets exactly the preset's seven columns, in order; GitHub's defaults ( Todo, In Progress, Done )
# are dropped and said so. A board with items keeps its options and only gets the missing ones appended, but only with --force, because
# GitHub's updateProjectV2Field replaces the whole option set ( ids change; cards keep their column by name in our tests, but check ).
# The view: the API has no mutation for views, so the project's first view stays a table named "View 1"; switch it to a Board layout
# in the browser ( the only manual step ).
# Settings ( language preset, column overrides ) come from .factory.json like board.sh.
set -euo pipefail
HERE=$( cd "$( dirname "$0" )" && pwd )
ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
cfg() { local v=""; [ -f "$CFG" ] && v=$( jq -r "$1 // empty" "$CFG" 2>/dev/null || true ); echo "${v:-$2}"; }
# shellcheck source=lang.sh
. "$HERE/lang.sh"
C_EPICS=$( cfg .columns.epics "$D_EPICS" ); C_BACKLOG=$( cfg .columns.backlog "$D_BACKLOG" ); C_READY=$( cfg .columns.ready "$D_READY" )
C_HUMAN=$( cfg .columns.human "$D_HUMAN" ); C_AGENT=$( cfg .columns.agent "$D_AGENT" ); C_REVIEW=$( cfg .columns.review "$D_REVIEW" ); C_DONE=$( cfg .columns.done "$D_DONE" )

# the preset as JSON options ( name, color, description ), in board order
preset() {
	jq -n --arg e "$C_EPICS" --arg b "$C_BACKLOG" --arg r "$C_READY" --arg h "$C_HUMAN" --arg a "$C_AGENT" --arg v "$C_REVIEW" --arg d "$C_DONE" '[
		{ name: $e, color: "PURPLE", description: "Umbrella tickets that group many smaller ones" },
		{ name: $b, color: "GRAY",   description: "Ideas and tickets, sorted by the owner, most important on top" },
		{ name: $r, color: "BLUE",   description: "Fully specified and ready, not started" },
		{ name: $h, color: "YELLOW", description: "Manual work the owner does" },
		{ name: $a, color: "ORANGE", description: "An agent is working on it right now" },
		{ name: $v, color: "PINK",   description: "Branch pushed ( merged ), waiting for the review of the owner" },
		{ name: $d, color: "GREEN",  description: "Approved by the owner" } ]'
}

cmd_columns() {
	local p=${1:-} o=${2:-} force=0; shift 2 || true; [ "${1:-}" = "--force" ] && force=1
	[ -n "$p" ] && [ -n "$o" ] || { echo 'usage: project.sh columns <project> <owner> [--force]' >&2; exit 2; }
	local pid st
	pid=$( gh project view "$p" --owner "$o" --format json --jq .id ) || { echo "project.sh: cannot read project $p of $o" >&2; exit 1; }
	local q='query($id: ID!) { node(id: $id) { ... on ProjectV2 { items { totalCount } field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name color description } } } } } }'
	st=$( gh api graphql -f query="$q" -f id="$pid" ) || exit 1
	local fid count have missing
	fid=$( jq -r '.data.node.field.id' <<< "$st" ); count=$( jq -r '.data.node.items.totalCount' <<< "$st" )
	have=$( jq -c '[ .data.node.field.options[] | { name, color, description: ( .description // "" ) } ]' <<< "$st" )
	missing=$( jq -c --argjson have "$have" '[ .[] | select( .name as $n | ( $have | map( .name ) | index( $n ) ) == null ) ]' <<< "$( preset )" )
	local names_have names_missing
	names_have=$( jq -r 'map( .name ) | join( ", " )' <<< "$have" ); names_missing=$( jq -r 'map( .name ) | join( ", " )' <<< "$missing" )
	if [ "$( jq length <<< "$missing" )" = 0 ]; then echo "columns ok: $names_have"; return 0; fi
	local options
	if [ "$count" = 0 ]; then
		options=$( preset )
		local dropped; dropped=$( jq -r --argjson want "$options" '[ .[] | select( .name as $n | ( $want | map( .name ) | index( $n ) ) == null ) | .name ] | join( ", " )' <<< "$have" )
		[ -z "$dropped" ] || echo "empty board: dropping the columns $dropped"
	elif [ $force = 1 ]; then
		options=$( jq -c --argjson m "$missing" '. + $m' <<< "$have" )
		echo "board has $count items: appending $names_missing ( option ids change; check the cards afterwards )" >&2
	else
		jq -r '.[] | "MISSING  column \"\( .name )\" is not an option of the Status field"' <<< "$missing" >&2
		echo "project.sh: the board has $count items; run \"project.sh columns $p $o --force\" to append the missing columns, or add them under Project settings > Status" >&2
		return 1
	fi
	jq -n --arg q 'mutation($input: UpdateProjectV2FieldInput!) { updateProjectV2Field(input: $input) { projectV2Field { ... on ProjectV2SingleSelectField { options { name } } } } }' \
		--arg f "$fid" --argjson opts "$options" '{ query: $q, variables: { input: { fieldId: $f, singleSelectOptions: $opts } } }' \
		| gh api graphql --input - --jq '"columns set: " + ( .data.updateProjectV2Field.projectV2Field.options | map( .name ) | join( ", " ) )'
}

cmd_create() {
	local owner="" repo="" title=""
	while [ $# -gt 0 ]; do case "$1" in
		--owner) owner=$2; shift ;; --repo) repo=$2; shift ;; --title) title=$2; shift ;;
		*) echo "unknown option $1" >&2; exit 2 ;; esac; shift; done
	[ -n "$repo" ] || repo=$( gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##' )
	[ -n "$repo" ] || { echo "project.sh: cannot tell the repository ( --repo owner/name )" >&2; exit 1; }
	[ -n "$owner" ] || owner=${repo%%/*}
	[ -n "$title" ] || title=${repo#*/}
	local n url linked all
	# what is there already: a project linked to the repository wins; several linked ones need the owner's choice; else one titled like the repo
	local q='query($o: String!, $r: String!) { repository(owner: $o, name: $r) { projectsV2(first: 20) { nodes { number title url closed } } } }'
	linked=$( gh api graphql -f query="$q" -f o="${repo%%/*}" -f r="${repo#*/}" --jq '[ .data.repository.projectsV2.nodes[] | select( .closed | not ) ]' 2>/dev/null || echo '[]' )
	case "$( jq length <<< "$linked" )" in
		1) n=$( jq -r '.[0].number' <<< "$linked" ); echo "using the project already linked to $repo: $n \"$( jq -r '.[0].title' <<< "$linked" )\" $( jq -r '.[0].url' <<< "$linked" )" >&2 ;;
		0) ;;
		*) echo "project.sh: $repo has several linked projects; pass the one to use as --project:" >&2; jq -r '.[] | "  \( .number )  \( .title )  \( .url )"' <<< "$linked" >&2; exit 3 ;;
	esac
	if [ -z "${n:-}" ]; then
		all=$( gh project list --owner "$owner" --format json --jq '[ .projects[] | select( .closed | not ) ]' 2>/dev/null || echo '[]' )
		n=$( jq -r --arg t "$title" '[ .[] | select( .title == $t ) ] | .[0].number // empty' <<< "$all" )
		if [ -n "$n" ]; then echo "using the owner's project titled like the repository: $n \"$title\" ( not yet linked )" >&2
		elif [ "$( jq length <<< "$all" )" != 0 ]; then echo "other projects of $owner ( none linked to $repo, none titled \"$title\" ); pass --project <n> to use one of them instead:" >&2; jq -r '.[] | "  \( .number )  \( .title )  \( .items.totalCount ) items"' <<< "$all" >&2; fi
	fi
	if [ -z "${n:-}" ]; then
		local pj; pj=$( gh project create --owner "$owner" --title "$title" --format json ) || exit 1
		n=$( jq -r .number <<< "$pj" ); url=$( jq -r .url <<< "$pj" ); echo "created project $n \"$title\" $url" >&2
	fi
	gh project link "$n" --owner "$owner" --repo "$repo" >/dev/null 2>&1 && echo "linked project $n to $repo" >&2 || echo "project.sh: could not link project $n to $repo ( already linked, or gh project link failed )" >&2
	cmd_columns "$n" "$owner" >&2 || echo "project.sh: the board keeps its columns; map them in .factory.json under \"columns\" or extend with --force" >&2
	echo "the first view is a table named \"View 1\": switch it to the Board layout in the browser ( no API for views )" >&2
	echo "$n"
}

case "${1:-}" in
	create) shift; cmd_create "$@" ;;
	columns) shift; cmd_columns "$@" ;;
	*) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
