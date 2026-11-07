#!/usr/bin/env bash
# Writes or updates the Collaboration section of AGENTS.md and the Delegation section of CLAUDE.md of the repo you run it in, from the plugin's
# templates ( templates/<lang>/ ), creates the labels and .factory.json, and checks the board's columns.
#   init.sh [--project <n>] [--owner <handle>] [--name "<Full Name>"] [--lang en|de] [--verify "<cmd>"] [--run "<local run cmd>"]
#           [--umbrella "<branch, branch>"] [--replace-existing] [--dry-run]
# Existing values in .factory.json are the defaults for omitted flags; the owner defaults to the repository's owner on GitHub.
# Sections are replaced between their <!-- factory:...:start/end --> markers; an existing "## Collaboration" / "## Delegation (Claude Code)"
# section without markers is only replaced with --replace-existing; repo-specific items of the old section ( ports, umbrella branches, canon,
# tools ) are then moved to a "### Repo-specific" subsection after the markers and printed ( heuristic: review the result ).
set -euo pipefail
HERE=$( cd "$( dirname "$0" )" && pwd ); PLUGIN=$( dirname "$HERE" )
ROOT=$( git rev-parse --show-toplevel ); CFG=$ROOT/.factory.json
get() { [ -f "$CFG" ] && jq -r "$1 // empty" "$CFG" || true; }
OWNER=$( get .owner ); NAME=$( get .ownerName ); PROJECT=$( get .project ); LANG_OPT=$( get .lang ); VERIFY=$( get '.verify[0].cmd' ); RUN=$( get .localRun )
UMB=$( get '.umbrella | if type == "array" then join(", ") else . end' )
REPLACE=0; DRY=0
while [ $# -gt 0 ]; do case "$1" in
	--owner) OWNER=$2; shift ;; --name) NAME=$2; shift ;; --project) PROJECT=$2; shift ;; --lang) LANG_OPT=$2; shift ;; --verify) VERIFY=$2; shift ;;
	--run) RUN=$2; shift ;; --umbrella) UMB=$2; shift ;; --replace-existing) REPLACE=1 ;; --dry-run) DRY=1 ;;
	*) echo "unknown option $1" >&2; exit 2 ;; esac; shift; done
REPO=$( gh repo view --json nameWithOwner --jq .nameWithOwner )
[ -n "$OWNER" ] || OWNER=${REPO%%/*}
[ -n "$NAME" ] || NAME=$( gh api "users/$OWNER" --jq '.name // .login' 2>/dev/null || echo "$OWNER" )
[ -n "$PROJECT" ] || { echo "init.sh: --project <number> is required ( gh project list --owner $OWNER )" >&2; exit 2; }
LANG_OPT=${LANG_OPT:-en}
[ -d "$PLUGIN/templates/$LANG_OPT" ] || { echo "init.sh: no templates for --lang $LANG_OPT ( available: $( ls "$PLUGIN/templates" | tr '\n' ' ' ))" >&2; exit 2; }
[ -n "$VERIFY" ] || VERIFY="npm run build"
[ -n "$RUN" ] || RUN="npm install && npm run dev"
PNAME=$( gh project view "$PROJECT" --owner "$OWNER" --format json --jq .title )
PURL=$( gh project view "$PROJECT" --owner "$OWNER" --format json --jq .url )
PLUGIN_URL=$( jq -r '.repository // "AgentKit"' "$PLUGIN/.claude-plugin/plugin.json" 2>/dev/null || echo AgentKit )
UNOTE=""; [ -z "$UMB" ] || UNOTE=", e.g. $( printf '%s' "$UMB" | sed 's/[^, ][^,]*/`&`/g' )"
MAIN=$( git worktree list --porcelain | awk 'NR == 1 { print $2 }' )   # sessions run in the main checkout, not in a ticket worktree
TDIR=$( printf '%s' "${MAIN:-$ROOT}" | sed 's/[\/.]/-/g' )

export OWNER NAME PROJECT PNAME PURL VERIFY RUN UNOTE TDIR PLUGIN_URL
render() { # render <template>
	python3 -c '
import os, sys
s = open(sys.argv[1]).read()
for k, e in { "OWNER": "OWNER", "OWNER_NAME": "NAME", "PROJECT": "PROJECT", "PROJECT_NAME": "PNAME", "PROJECT_URL": "PURL", "VERIFY": "VERIFY",
              "LOCAL_RUN": "RUN", "UMBRELLA_NOTE": "UNOTE", "TRANSCRIPT_DIR": "TDIR", "PLUGIN_URL": "PLUGIN_URL" }.items():
	s = s.replace("{{" + k + "}}", os.environ[e])
sys.stdout.write(s)' "$1"
}

# install <file> <section name> <marker> <rendered file>
install() {
	local file=$1 head=$2 marker=$3 new=$4
	[ -f "$file" ] || { [ $DRY = 1 ] || printf '# %s\n\n' "$( basename "${MAIN:-$ROOT}" )" > "$file"; [ "$( basename "$file" )" != CLAUDE.md ] || printf '@AGENTS.md\n\n' >> "$file"; }
	[ -f "$file" ] || return 0
	if grep -q "factory:$marker:start" "$file"; then
		awk -v m="$marker" -v nf="$new" '
			$0 ~ "factory:" m ":start" { while ( ( getline l < nf ) > 0 ) print l; skip = 1; next }
			$0 ~ "factory:" m ":end" { skip = 0; next }
			! skip { print }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"; echo "updated $file ( $marker )"
	elif grep -q "^## $head" "$file"; then
		if [ $REPLACE = 1 ]; then
			# repo-specific items of the old section ( ports, umbrella branches, canon, tools ... ) that the template does not already say
			# are moved into a "### Repo-specific" subsection after the end marker, and printed
			python3 - "$file" "## $head" "$new" "$marker" <<'PY'
import sys, re, difflib
file, head, nf, marker = sys.argv[1:5]
lines = open(file).read().split("\n")
new = open(nf).read().rstrip("\n").split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith(head))
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
old = lines[start:end]
# split into items: a bullet, or a paragraph; code fences stay whole
items, cur, fence = [], [], False
for l in old[1:]:
	if l.startswith("```"): fence = not fence
	top = not fence and ( l.startswith("- ") or l.startswith("### ") or ( not l.strip() ) )
	if top and cur: items.append(cur); cur = []
	if l.strip() or fence: cur.append(l)
if cur: items.append(cur)
newitems, cur = [], []
for l in new:
	if l.startswith("- ") or l.startswith("### ") or not l.strip():
		if cur: newitems.append(" ".join(cur)); cur = []
	if l.strip(): cur.append(l.strip())
if cur: newitems.append(" ".join(cur))
KEY = re.compile(r"\bports?\b|umbrella|canon|watchdog|\btools?\b|VPS|delete_branch|backend|preview|\bnpm\b|\bpnpm\b", re.I)
moved = []
for it in items:
	t = " ".join(x.strip() for x in it)
	if t.startswith("###") or t.startswith("```") or not KEY.search(t): continue
	if max( ( difflib.SequenceMatcher(None, t, n).ratio() for n in newitems ), default = 0 ) > 0.55: continue
	moved.append(it)
out = lines[:start] + new
rest = lines[end:]
body = []
if moved:
	body = ["", "### Repo-specific", "", "Kept from the repository's earlier Collaboration section; not part of the plugin's rules."] + [""] + [l for it in moved for l in it]
	print("moved %d repo-specific item(s) of %s to \"### Repo-specific\":" % (len(moved), file))
	for it in moved: print("  | " + it[0][:140])
open(file, "w").write("\n".join(out + body + [""] + rest if rest else out + body) + ("\n" if not rest else ""))
PY
			echo "replaced existing section in $file"
		else echo "$file has a \"## $head\" section without markers: run again with --replace-existing to replace it" >&2; return 1; fi
	else
		{ printf '\n'; cat "$new"; } >> "$file"; echo "appended to $file"
	fi
}

TMP=$( mktemp -d ); render "$PLUGIN/templates/$LANG_OPT/AGENTS.collaboration.md" > "$TMP/a.md"; render "$PLUGIN/templates/$LANG_OPT/CLAUDE.delegation.md" > "$TMP/c.md"
if [ $DRY = 1 ]; then cat "$TMP/a.md" "$TMP/c.md"; echo "--- dry run: nothing written" >&2; rm -rf "$TMP"; exit 0; fi

rc=0
install "$ROOT/AGENTS.md" Collaboration collaboration "$TMP/a.md" || rc=1
install "$ROOT/CLAUDE.md" "Delegation (Claude Code)" delegation "$TMP/c.md" || rc=1
grep -q '@AGENTS.md' "$ROOT/CLAUDE.md" 2>/dev/null || echo "note: CLAUDE.md does not import AGENTS.md ( add a line @AGENTS.md ) so Claude Code reads the Collaboration section" >&2
rm -rf "$TMP"

# .factory.json: keep what is there, set what is known
BASE='{}'; [ -f "$CFG" ] && BASE=$( cat "$CFG" )
echo "$BASE" | jq --argjson p "$PROJECT" --arg o "$OWNER" --arg n "$NAME" --arg l "$LANG_OPT" --arg run "$RUN" --arg v "$VERIFY" --arg u "$UMB" '
	.project = $p | .owner = $o | .ownerName = $n | .lang = $l | .reviewer = (.reviewer // $o) | .localRun = $run
	| .verify = (.verify // [ { name: "Build", cmd: $v } ])
	| .umbrella = (.umbrella // ( if $u == "" then [] else ( $u | split(", ") ) end ) )' > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
echo "wrote $CFG"

# labels ( names follow the lang preset; existing labels are kept )
. "$HERE/lang.sh"
declare -a L=( "$D_L_IDEA:FBCA04:Idea, not yet specified" "feature:1D76DB:New capability" "bug:D73A4A:Something is broken" "documentation:0075CA:Docs only" "$D_L_MERGED:0E8A16:Agent merged the branch, waiting for the owner's review" )
for l in "${L[@]}"; do IFS=: read -r n c d <<< "$l"; gh label create "$n" --repo "$REPO" --color "$c" --description "$d" >/dev/null 2>&1 && echo "label $n created" || echo "label $n exists"; done

# the board's columns
"$HERE/board.sh" ids "$PROJECT" "$OWNER" || { echo "init.sh: add the missing columns in the project's Status field ( Project settings > Status )" >&2; rc=1; }
exit $rc
