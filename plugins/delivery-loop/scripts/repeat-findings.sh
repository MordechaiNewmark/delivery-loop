#!/usr/bin/env bash
# repeat-findings.sh [--min N] — review corrections that keep recurring.
#
# "Correct once, enforce forever" (spec §2.1, §9): a finding a reviewer has had
# to make on N (default 2) different agent PRs is a rule the harness should
# ENFORCE (a gate check, a lint rule, a test, a banned import) instead of a
# reviewer re-teaching it in prose. This lists every such finding that has no
# enforcement task yet, so the patcher can file one.
#
# Reviewers tag findings as `Finding <key>: <what; the fix>` lines (review-task).
# A filed enforcement task carries `enforce:<key>` in its title, which retires
# the key from this list. Logic: lib/repeat-findings.jq (pure, unit-tested).
#
# Output: "<key> <pr-count> #pr #pr ..." per line, most-repeated first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MIN=2
if [ "${1:-}" = "--min" ]; then MIN="${2:?usage: repeat-findings.sh [--min N]}"; fi

prs=$(gh pr list --state all --label agent-authored --limit 200 --json number,reviews)
tasks=$(gh issue list --state all --label task --limit 1000 --json title)

jq -n --argjson prs "$prs" --argjson issues "$tasks" '{prs: $prs, issues: $issues}' \
  | jq -r --argjson min "$MIN" -f "$SCRIPT_DIR/lib/repeat-findings.jq"
