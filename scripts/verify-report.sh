#!/usr/bin/env bash
# One command that runs the repo's checks and prints a finished ticket section: PASS / FAIL per check, exit code 1 on any FAIL.
#   verify-report.sh [--quick] [--timeout 900]
# The checks are listed in .factory.json at the repo root:
#   "verify": [ { "name": "Build", "cmd": "npm run build" }, { "name": "Pictures", "cmd": "node picdiff.mjs a b --fail 6", "slow": true } ]
# A string entry is its own name. "slow": true entries are skipped with --quick. Each command runs under run.sh ( timeout, orphaned Chromes ).
# The section's wording follows the "lang" preset of .factory.json ( lang.sh ). It goes to stdout, to be pasted into the ticket
# ( `gh issue comment <n> --body-file -` ); progress goes to stderr.
set -uo pipefail
HERE=$( cd "$( dirname "$0" )" && pwd )
ROOT=$( git rev-parse --show-toplevel 2>/dev/null || pwd )
CFG=${FACTORY_JSON:-$ROOT/.factory.json}
# shellcheck source=lang.sh
. "$HERE/lang.sh"
QUICK=0; LIMIT=900
while [ $# -gt 0 ]; do case "$1" in --quick) QUICK=1 ;; --timeout) LIMIT=$2; shift ;; *) echo "unknown $1" >&2; exit 2 ;; esac; shift; done
[ -f "$CFG" ] && [ "$( jq '.verify | length // 0' "$CFG" )" -gt 0 ] || { echo "verify-report.sh: no \"verify\" list in $CFG" >&2; exit 2; }
cd "$ROOT"
sha=$( git rev-parse --short HEAD )
rows=""; fail=0
while IFS=$'\t' read -r name cmd slow; do
	if [ "$QUICK" = 1 ] && [ "$slow" = "true" ]; then rows+="| $name | $D_T_SKIPPED (--quick) |"$'\n'; continue; fi
	echo "[verify] $name: $cmd" >&2
	out=$( "$HERE/run.sh" "$LIMIT" bash -c "$cmd" 2>&1 ); rc=$?
	tail1=$( printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-120 | tr '|' '/' )
	if [ $rc -eq 0 ]; then rows+="| $name | PASS: ${tail1:-ok} |"$'\n'; else rows+="| $name | FAIL: $D_T_CODE $rc, ${tail1:-$D_T_NO_OUTPUT} |"$'\n'; fail=1; fi
done < <( jq -r '.verify[] | if type == "string" then [ ., ., "false" ] else [ ( .name // .cmd ), .cmd, ( .slow // false | tostring ) ] end | @tsv' "$CFG" )
verdict=PASS; [ $fail = 1 ] && verdict=FAIL
printf '**%s (verify-report.sh, %s `%s`%s): %s**\n\n| %s | %s |\n|---|---|\n%s' "$D_T_REPORT" "$D_T_STATE" "$sha" "$( [ $QUICK = 1 ] && echo ', --quick' )" "$verdict" "$D_T_CHECK" "$D_T_RESULT" "$rows"
exit $fail
