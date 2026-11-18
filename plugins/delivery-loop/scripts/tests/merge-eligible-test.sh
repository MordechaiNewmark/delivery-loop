#!/usr/bin/env bash
# Regression tests for scripts/lib/merge-eligible.jq — the auto-merge gate.
#
# Feeds synthetic `gh pr view` payloads (no GitHub calls) and asserts the
# verdict. The gate is "review evidence, not diffs": a PR merges itself only when
# it is approved, green, carries an Evidence section, and stays out of the paths
# the operator reserved for human merge (HUMAN_MERGE_PATHS).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="$here/../lib/merge-eligible.jq"

# A fully eligible PR; each case below breaks exactly one thing.
base='{
  "pr": {
    "state": "OPEN", "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN",
    "statusCheckRollup": [{"name": "gate", "conclusion": "SUCCESS"},
                          {"context": "legacy", "state": "SUCCESS"}],
    "labels": [{"name": "agent-authored"}],
    "body": "Closes #7\n\n## Evidence\n- `bash scripts/check.sh` -> gate passed",
    "files": [{"path": "src/parser/lex.py"}, {"path": "tests/test_lex.py"}]
  },
  "issueLabels": ["task", "status:approved"]
}'

fails=0
check() {
  local name="$1" paths="$2" patch="$3" expected="$4" got
  got=$(jq "$patch" <<<"$base" | jq -r --arg paths "$paths" -f "$filter")
  if [ "$got" = "$expected" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name" >&2
    echo "        expected: [$expected]" >&2
    echo "        got:      [$got]" >&2
    fails=1
  fi
}

check "approved, green, evidenced -> eligible" "" '.' "eligible"
check "issue not approved -> hold" "" '.issueLabels = ["status:in-review"]' \
  "hold: linked issue is not status:approved"
check "needs-human -> hold" "" '.pr.labels += [{"name": "needs-human"}]' \
  "hold: labeled needs-human"
check "conflicting -> hold" "" '.pr.mergeable = "CONFLICTING" | .pr.mergeStateStatus = "DIRTY"' \
  "hold: not mergeable (CONFLICTING)"
check "no checks at all -> hold" "" '.pr.statusCheckRollup = []' \
  "hold: no CI checks — a PR without a green check is unreviewable"
check "pending check -> hold, names it" "" '.pr.statusCheckRollup[0].conclusion = null' \
  "hold: a check is not SUCCESS: gate"
check "no Evidence section -> hold" "" '.pr.body = "Closes #7\n\nSummary only."' \
  "hold: PR body has no Evidence section — nothing for a human to review"
check "evidence heading is case-insensitive, any depth" "" '.pr.body = "### EVIDENCE (runtime)\nok"' \
  "eligible"
check "single * stays in one segment" "src/*.py" '.' "eligible"
check "** crosses segments -> hold, names the file" "src/**.py" '.' \
  "hold: touches HUMAN_MERGE_PATHS: src/parser/lex.py"
check "trailing / guards a whole directory" "docs/ tests/" '.' \
  "hold: touches HUMAN_MERGE_PATHS: tests/test_lex.py"
check "dots are literal, not regex" "tests/test_lexXpy" '.pr.files = [{"path": "tests/test_lex.py"}]' \
  "eligible"
check "first unmet condition wins" "" '.pr.state = "MERGED" | .issueLabels = []' \
  "hold: PR is MERGED"

if [ "$fails" -ne 0 ]; then
  echo "merge-eligible tests FAILED" >&2
  exit 1
fi
echo "merge-eligible tests passed"
