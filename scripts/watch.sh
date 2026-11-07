#!/usr/bin/env bash
# Session watcher for Claude Code's Monitor tool: prints one line per change, nothing otherwise.
#   watch.sh [issue number ...]
# - per issue: its board column, assignees and labels ( gh issue view --json projectItems,assignees,labels ), e.g. "#31 column Zur Review"
# - per session transcript of this project ( ~/.claude/projects/<project>/<session>.jsonl ): a new transcript, and one going quiet
#   ( no write for QUIET seconds: finished, or waiting for an answer )
# Env: INTERVAL ( seconds between polls, default 30 ), QUIET ( default 300 ), TRANSCRIPTS ( directory, default derived from the current directory ),
#      FACTORY_JSON ( settings file, default <repo>/.factory.json )
# Monitor it:  Monitor( command: "$CLAUDE_PLUGIN_ROOT/scripts/watch.sh 31 32", ... ). Stops when the session that started it ends.
INTERVAL=${INTERVAL:-30}
QUIET=${QUIET:-300}
ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
REPO=""
[ -f "$CFG" ] && command -v jq >/dev/null && REPO=$( jq -r '.repo // empty' "$CFG" )
[ -n "$REPO" ] || REPO=$( gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null )
# Claude Code names a project's transcript directory after its path: every / and . becomes -
TR=${TRANSCRIPTS:-$HOME/.claude/projects/$( printf '%s' "$ROOT" | sed 's/[\/.]/-/g' )}
STATE=$( mktemp -d ); trap 'rm -rf "$STATE"' EXIT
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }
emit() { printf '%s %s\n' "$( date +%H:%M:%S )" "$*"; }

[ -d "$TR" ] && emit "watching transcripts in $TR"
first=1
while true; do
	for n in "$@"; do
		line=$( gh issue view "$n" --repo "$REPO" --json projectItems,assignees,labels,state \
			--jq '"column \( [ .projectItems[] | .status.name ] | join(",") ); assignees \( [ .assignees[].login ] | join(",") ); labels \( [ .labels[].name ] | join(",") ); \(.state)"' 2>/dev/null ) || continue
		if [ "$line" != "$( cat "$STATE/i$n" 2>/dev/null )" ]; then
			printf '%s' "$line" > "$STATE/i$n"
			emit "#$n $line"
		fi
	done
	if [ -d "$TR" ]; then
		now=$( date +%s )
		for f in "$TR"/*.jsonl; do
			[ -e "$f" ] || continue
			id=$( basename "$f" .jsonl ); m=$( mtime "$f" ); age=$(( now - m )); st="active"
			[ "$age" -ge "$QUIET" ] && st="quiet"
			prev=$( cat "$STATE/t$id" 2>/dev/null )
			[ "$st" = "$prev" ] && continue
			printf '%s' "$st" > "$STATE/t$id"
			if [ -z "$prev" ]; then
				# first pass: only sessions that are active right now; later: every new transcript
				if [ $first -eq 1 ]; then [ "$st" = "active" ] && emit "session ${id:0:8} active ( last write ${age}s ago )"
				else emit "session ${id:0:8} new transcript"; fi
			else
				emit "session ${id:0:8} $st ( last write ${age}s ago )"
			fi
		done
	fi
	first=0
	sleep "$INTERVAL"
done
