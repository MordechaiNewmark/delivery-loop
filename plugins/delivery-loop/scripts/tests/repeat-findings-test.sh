#!/usr/bin/env bash
# Regression tests for scripts/lib/repeat-findings.jq — "correct once, enforce
# forever". Feeds synthetic review histories (no GitHub calls) and asserts which
# findings are reported as due for enforcement.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
filter="$here/../lib/repeat-findings.jq"

fails=0
check() {
  local name="$1" min="$2" input="$3" expected="$4" got
  got=$(jq -r --argjson min "$min" -f "$filter" <<<"$input")
  if [ "$got" = "$expected" ]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name" >&2
    echo "        expected: [$expected]" >&2
    echo "        got:      [$got]" >&2
    fails=1
  fi
}

check "same finding on two PRs -> due" 2 '{
  "prs": [
    {"number": 11, "reviews": [{"body": "Changes requested.\n- Finding raw-sql: string-built query; use the query builder."}]},
    {"number": 14, "reviews": [{"body": "Finding raw-sql: f-string SQL in repo.py; use bound params."}]}
  ],
  "issues": []
}' "raw-sql 2 #11 #14"

check "repeat within ONE PR's patch rounds counts once" 2 '{
  "prs": [
    {"number": 11, "reviews": [{"body": "Finding raw-sql: first round"},
                               {"body": "Finding raw-sql: still there in round 2"}]}
  ],
  "issues": []
}' ""

check "already filed as enforce:<key> -> retired" 2 '{
  "prs": [
    {"number": 11, "reviews": [{"body": "Finding raw-sql: a"}]},
    {"number": 14, "reviews": [{"body": "Finding raw-sql: b"}]}
  ],
  "issues": [{"title": "Ban string-built SQL in the gate (enforce:raw-sql)"}]
}' ""

check "most-repeated first; prose mentions and bad keys ignored" 2 '{
  "prs": [
    {"number": 3, "reviews": [{"body": "Finding no-print: a\n* Finding cross-import: b"}]},
    {"number": 5, "reviews": [{"body": "Finding no-print: c\nThe Finding no-print: inline mention does not count"}]},
    {"number": 8, "reviews": [{"body": "Finding no-print: d\nFinding cross-import: e\nFinding Not_Kebab: f"}]}
  ],
  "issues": []
}' "no-print 3 #3 #5 #8
cross-import 2 #3 #8"

check "approvals with no findings -> nothing" 2 '{
  "prs": [{"number": 1, "reviews": [{"body": "All criteria pass."}, {"body": null}]}],
  "issues": []
}' ""

if [ "$fails" -ne 0 ]; then
  echo "repeat-findings tests FAILED" >&2
  exit 1
fi
echo "repeat-findings tests passed"
