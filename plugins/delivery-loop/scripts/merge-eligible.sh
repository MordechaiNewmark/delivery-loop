#!/usr/bin/env bash
# merge-eligible.sh <pr> — may this approved agent PR merge itself?
#
# The auto-merge gate (spec §8.2, §11.1), as code rather than prose: the
# orchestrator calls it for every candidate under --auto-merge and merges only on
# exit 0. Eligible iff ALL hold —
#   * the PR is OPEN, MERGEABLE, mergeStateStatus CLEAN, not needs-human
#   * its linked issue (`Closes #N`) is status:approved
#   * it has >= 1 CI check and every check is SUCCESS
#   * its body carries an Evidence section (humans review proof, not diffs)
#   * it touches no path in HUMAN_MERGE_PATHS (those always wait for a human)
# The decision itself is lib/merge-eligible.jq (pure, unit-tested).
#
# Prints "eligible" (exit 0) or "hold: <reason>" (exit 1).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
. "$SCRIPT_DIR/lib/config.sh"

PR=${1:?usage: merge-eligible.sh <pr>}

pr_json=$(gh pr view "$PR" --json state,mergeable,mergeStateStatus,statusCheckRollup,labels,body,files)
issue=$(jq -r '[.body // "" | scan("(?i)(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?) #([0-9]+)")[0]] | first // empty' <<<"$pr_json")

issue_labels='[]'
if [ -n "$issue" ]; then
  issue_labels=$(gh issue view "$issue" --json labels --jq '[.labels[].name]')
fi

verdict=$(jq -n --argjson pr "$pr_json" --argjson il "$issue_labels" '{pr: $pr, issueLabels: $il}' \
  | jq -r --arg paths "$HUMAN_MERGE_PATHS" -f "$SCRIPT_DIR/lib/merge-eligible.jq")

echo "$verdict"
[ "$verdict" = "eligible" ]
