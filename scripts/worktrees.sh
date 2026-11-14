#!/usr/bin/env bash
# Keeps the repository's worktrees and branches down to what is still in work. Dry run by default: prints what it would remove.
#   worktrees.sh [--apply] [--remote] [--json]
# A worktree goes when all of these hold: it is not the main checkout, not locked ( `git worktree lock <path>` keeps one for good ), not on a base branch, its HEAD is contained in a base branch ( the remote
# default branch and every branch in "umbrella" of .factory.json ), it has no changed tracked file and no untracked file that is not
# ignored, and no process has its working directory inside it ( a dev server, a builder ). Ignored files ( dependencies, builds ) go with it.
# Then local branches contained in a base and checked out nowhere are deleted. --remote also deletes remote branches contained in a
# base ( never a base itself ); that changes the shared repository, so run it only with the owner's go.
# Always prints the counts before and after, and warns when more worktrees remain than "agentsMax" + 2 ( .factory.json, default 6 ).
# --json: { worktrees, kept: [ { path, branch, reason } ], removed: [ … ], branchesDeleted, remoteDeleted, warn }. Exits 0.
APPLY=0; REMOTE=0; JSON=0
for a in "$@"; do case "$a" in --apply) APPLY=1 ;; --remote) REMOTE=1 ;; --json) JSON=1 ;; *) echo "usage: worktrees.sh [--apply] [--remote] [--json]" >&2; exit 0 ;; esac; done

ROOT=$( git rev-parse --show-toplevel 2>/dev/null ) || { echo "worktrees.sh: not in a git repository" >&2; exit 0; }
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
cfg() { # cfg <jq expr> <default>
	local v=""
	[ -f "$CFG" ] && command -v jq >/dev/null && v=$( jq -r "$1 // empty" "$CFG" 2>/dev/null || true )
	echo "${v:-$2}"
}
AMAX=$( cfg .agentsMax 6 )
git fetch -q --prune origin 2>/dev/null || true
DEF=$( git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' ); DEF=${DEF:-main}
BASES="$DEF $( cfg '.umbrella | join(" ")' '' )"
contained() { # contained <rev>: in any base on origin
	local b
	for b in $BASES; do git merge-base --is-ancestor "$1" "origin/$b" 2>/dev/null && return 0; done
	return 1
}
isbase() { case " $BASES " in *" $1 "*) return 0 ;; esac; return 1; }
MAIN=$( git worktree list --porcelain | awk '/^worktree /{ print $2; exit }' )
CWDS=$( lsof -nP -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' )

kept=(); removed=(); before=$( git worktree list | wc -l | tr -d ' ' )
while IFS='|' read -r w h b locked; do
	[ -n "$w" ] || continue
	br=${b#refs/heads/}; why=""
	if [ "$w" = "$MAIN" ]; then why="main checkout"
	elif [ -n "$locked" ]; then why="locked"
	elif isbase "$br"; then why="a base branch"
	elif [ ! -d "$w" ]; then why=""
	elif ! contained "$h"; then why="not merged"
	elif [ -n "$( git -C "$w" status --porcelain --untracked-files=normal 2>/dev/null | head -1 )" ]; then why="uncommitted or untracked files"
	elif printf '%s\n' "$CWDS" | grep -q "^$w\(/\|$\)"; then why="a process works in it"
	fi
	if [ -n "$why" ]; then kept+=( "$w|$br|$why" ); continue; fi
	if [ "$APPLY" = 1 ]; then git worktree remove --force "$w" 2>/dev/null && removed+=( "$w|$br" ) || kept+=( "$w|$br|remove failed" )
	else removed+=( "$w|$br" ); fi
done < <( git worktree list --porcelain | awk '/^worktree /{ w = $2; h = ""; b = ""; l = "" } /^HEAD /{ h = $2 } /^branch /{ b = $2 } /^locked/{ l = "y" } /^$/{ print w "|" h "|" b "|" l }' )
[ "$APPLY" = 1 ] && git worktree prune

# local branches: contained in a base, not a base, checked out nowhere
out=$( git worktree list --porcelain | sed -n 's|^branch refs/heads/||p' ); bdel=0
for br in $( git for-each-ref --format='%(refname:short)' refs/heads ); do
	isbase "$br" && continue
	printf '%s\n' "$out" | grep -qx "$br" && continue
	contained "$br" || continue
	if [ "$APPLY" = 1 ]; then git branch -q -D "$br" && bdel=$(( bdel + 1 )); else bdel=$(( bdel + 1 )); fi
done
rdel=0
if [ "$REMOTE" = 1 ]; then
	list=()
	for br in $( git for-each-ref --format='%(refname:short)' refs/remotes/origin | sed -n 's|^origin/||p' ); do
		[ "$br" = HEAD ] && continue; isbase "$br" && continue
		contained "origin/$br" && list+=( "$br" )
	done
	rdel=${#list[@]}
	if [ "$APPLY" = 1 ] && [ "$rdel" -gt 0 ]; then printf '%s\n' "${list[@]}" | xargs -n 20 git push -q origin --delete 2>/dev/null; git fetch -q --prune origin; fi
fi
after=$(( before - ( APPLY ? ${#removed[@]} : 0 ) )); warn=""
[ "$after" -gt $(( AMAX + 2 )) ] && warn="$after worktrees remain, more than agentsMax + 2 = $(( AMAX + 2 )): look at the kept ones"
# leftovers of a shell loop that did not split its words ( zsh ): a worktree path with a space in it, a local branch named like a remote one
stray=$( { git worktree list --porcelain | sed -n 's/^worktree //p' | grep ' ' | sed 's/^/worktree path with a space: /'; git for-each-ref --format='%(refname:short)' refs/heads/origin/ | sed 's/^/local branch named like a remote one: /'; } 2>/dev/null || true )
[ -n "$stray" ] && warn="${warn:+$warn; }$( printf '%s' "$stray" | tr '\n' ';' )"

if [ "$JSON" = 1 ]; then
	jq -n --argjson wt "$before" --arg k "$( printf '%s\n' "${kept[@]}" )" --arg r "$( printf '%s\n' "${removed[@]}" )" --argjson bd "$bdel" --argjson rd "$rdel" --arg warn "$warn" --argjson apply "$APPLY" \
		'{ apply: ( $apply == 1 ), worktrees: $wt, kept: [ $k | split("\n")[] | select( . != "" ) | split("|") | { path: .[0], branch: .[1], reason: .[2] } ], removed: [ $r | split("\n")[] | select( . != "" ) | split("|") | { path: .[0], branch: .[1] } ], branchesDeleted: $bd, remoteDeleted: $rd, warn: $warn }'
	exit 0
fi
verb=$( [ "$APPLY" = 1 ] && echo "removed" || echo "would remove" )
echo "worktrees: $before; $verb ${#removed[@]}; local branches $verb: $bdel$( [ "$REMOTE" = 1 ] && echo "; remote branches $verb: $rdel" )"
for x in "${removed[@]}"; do echo "  - ${x%%|*} ( ${x#*|} )"; done
echo "kept:"
for x in "${kept[@]}"; do IFS='|' read -r w br why <<< "$x"; echo "  ${w} ( ${br:-detached} ): $why"; done
[ -n "$warn" ] && echo "WARN: $warn"
[ "$APPLY" = 1 ] || echo "( dry run: --apply removes )"
exit 0
