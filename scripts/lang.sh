#!/usr/bin/env bash
# Language presets for the board's column names, the labels and the ticket wording. Sourced by board.sh, init.sh and verify-report.sh;
# every value can be overridden in .factory.json ( "columns", "labels", "terms" ). Expects $CFG to point at .factory.json ( may not exist ).
#   en ( default ): Epics, Backlog, Ready, In Progress (Human), In Progress (Agent), In Review, Done; labels idea / merged; line **Merged:**
#   de:             Epics, Backlog, Bereit, In Arbeit (Mensch), In Arbeit (Agent), Zur Review, Fertig; labels idee / gemergt; line **Gemergt:**
LANG_PRESET=en
[ -f "${CFG:-/nonexistent}" ] && LANG_PRESET=$( jq -r '.lang // "en"' "$CFG" 2>/dev/null || echo en )
case "$LANG_PRESET" in
	de)
		D_EPICS="Epics"; D_BACKLOG="Backlog"; D_READY="Bereit"; D_HUMAN="In Arbeit (Mensch)"; D_AGENT="In Arbeit (Agent)"; D_REVIEW="Zur Review"; D_DONE="Fertig"
		D_L_IDEA="idee"; D_L_MERGED="gemergt"; D_T_MERGED="Gemergt"
		D_T_REPORT="Prüfung"; D_T_CHECK="Prüfung"; D_T_RESULT="Ergebnis"; D_T_SKIPPED="ausgelassen"; D_T_CODE="Code"; D_T_NO_OUTPUT="keine Ausgabe"; D_T_STATE="Stand"
		;;
	*)
		D_EPICS="Epics"; D_BACKLOG="Backlog"; D_READY="Ready"; D_HUMAN="In Progress (Human)"; D_AGENT="In Progress (Agent)"; D_REVIEW="In Review"; D_DONE="Done"
		D_L_IDEA="idea"; D_L_MERGED="merged"; D_T_MERGED="Merged"
		D_T_REPORT="Verification"; D_T_CHECK="Check"; D_T_RESULT="Result"; D_T_SKIPPED="skipped"; D_T_CODE="exit"; D_T_NO_OUTPUT="no output"; D_T_STATE="at"
		;;
esac
export LANG_PRESET D_EPICS D_BACKLOG D_READY D_HUMAN D_AGENT D_REVIEW D_DONE D_L_IDEA D_L_MERGED D_T_MERGED D_T_REPORT D_T_CHECK D_T_RESULT D_T_SKIPPED D_T_CODE D_T_NO_OUTPUT D_T_STATE
