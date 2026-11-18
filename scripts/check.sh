#!/usr/bin/env bash
# check.sh — THE verification gate for this repo.
#
# The single definition of "is this repo correct": the delivery loop runs this
# identically for implementers, reviewers, and patchers (it is GATE_CMD in
# .claude/delivery.conf). Change what "correct" means HERE, nowhere else.
#
# This repo dogfoods the delivery-loop plugin it ships, so the gate encodes the
# package's own invariants: every script parses, the claim logic's unit tests
# pass, the manifests validate and agree on the version, and no consumer-specific
# string has leaked into the shipped plugin. Requires the `claude` CLI on PATH.
#
# Every FAIL names its fix: an agent that trips a check should know what to
# change without asking (spec §11, "gate failures name the fix").
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo '==> bash -n: every script parses'
for f in $(find plugins scripts -name '*.sh'); do bash -n "$f"; done

echo '==> jq logic unit tests (claim lock, auto-merge gate, repeat findings)'
for t in plugins/delivery-loop/scripts/tests/*-test.sh; do bash "$t"; done

echo '==> plugin manifest validates'
claude plugin validate ./plugins/delivery-loop

echo '==> manifest versions agree (plugin.json == marketplace.json)'
plugin_v="$(jq -r .version plugins/delivery-loop/.claude-plugin/plugin.json)"
market_v="$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json)"
if [ "$plugin_v" != "$market_v" ]; then
  echo "FAIL: plugin.json ($plugin_v) != marketplace.json ($market_v)." >&2
  echo "      Fix: set the same \"version\" in plugins/delivery-loop/.claude-plugin/plugin.json and .claude-plugin/marketplace.json." >&2
  exit 1
fi

echo '==> no consumer-specific strings in plugins/'
if grep -rin lineage plugins/ >&2; then
  echo "FAIL: consumer-specific string leaked into the shipped plugin (above)." >&2
  echo "      Fix: route it through a .claude/delivery.conf key (CLAUDE.md, \"The cardinal rule\")." >&2
  exit 1
fi

echo '==> every skill has a row in the README skill table'
for d in plugins/delivery-loop/skills/*/; do
  skill="$(basename "$d")"
  if ! grep -q "^| \`$skill\` |" README.md; then
    echo "FAIL: skill '$skill' has no row in README.md's skill table." >&2
    echo "      Fix: add a '| \`$skill\` | <role> |' row to the table under \"What you get\", and its one-liner to plugins/delivery-loop/README.md." >&2
    exit 1
  fi
done

echo "==> gate passed"
