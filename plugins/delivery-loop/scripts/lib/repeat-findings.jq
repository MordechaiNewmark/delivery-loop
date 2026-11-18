# repeat-findings.jq — find review corrections that keep recurring (spec §9).
#
# Input:  {"prs":    [{"number": N, "reviews": [{"body": "..."}]}],   # agent PRs
#          "issues": [{"title": "..."}]}                              # all tasks
# Args:   --argjson min <n>   report a finding seen on at least n distinct PRs.
# Output: one line per finding key: "<key> <pr-count> #a #b ...", most-repeated
#         first. A key that already has a task titled with `enforce:<key>` is
#         skipped — it has been filed, so it is no longer a prose correction.
#
# Reviewers tag each finding as a line `Finding <key>: <what is wrong; the fix>`
# (optionally bulleted), key = lowercase kebab-case. A key repeated across patch
# rounds of ONE PR counts once: "corrected twice" means on two different changes.

def finding_keys:
  split("\n")[] | capture("^\\s*(?:[-*]\\s*)?Finding (?<k>[a-z0-9][a-z0-9-]*):").k;

([.issues[]?.title | scan("enforce:([a-z0-9][a-z0-9-]*)")[0]]) as $filed
| [ .prs[] | .number as $n
    | ([.reviews[]?.body // "" | finding_keys] | unique)[]
    | {k: ., n: $n} ]
| group_by(.k)
| map({k: .[0].k, prs: (map(.n) | unique)})
| map(select((.prs | length) >= $min) | select(.k as $k | any($filed[]; . == $k) | not))
| sort_by(-(.prs | length), .k)
| .[]
| "\(.k) \(.prs | length) \(.prs | map("#\(.)") | join(" "))"
