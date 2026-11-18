# merge-eligible.jq — may an approved agent PR merge itself? (spec §8.2, §11.1)
#
# Input:  {"pr": <gh pr view --json state,mergeable,mergeStateStatus,
#                 statusCheckRollup,labels,body,files>,
#          "issueLabels": [<label names of the PR's linked issue>]}
# Args:   --arg paths "<HUMAN_MERGE_PATHS>"  space-separated globs ("" = none).
#         `*` stays inside one path segment, `**` crosses segments, a trailing
#         `/` matches everything under that directory.
# Output: "eligible", or "hold: <reason>" naming the FIRST unmet condition.
#
# Pure logic, no GitHub calls — unit-tested in tests/merge-eligible-test.sh.

def re_escape: gsub("(?<c>[.+^$(){}|\\[\\]\\\\])"; "\\\(.c)");
def glob_re:
  if endswith("/") then "^" + re_escape
  else "^" + (re_escape | gsub("\\*\\*"; "\u0001") | gsub("\\*"; "[^/]*")
              | gsub("\u0001"; ".*") | gsub("\\?"; "[^/]")) + "$"
  end;
def check_ok: ((.conclusion // .state // "") | ascii_upcase) == "SUCCESS";
def has_evidence: (. // "") | split("\n") | any(test("^#{2,}\\s*evidence\\b"; "i"));

($paths | split(" ") | map(select(length > 0))) as $globs
| .pr as $pr
| ([$pr.labels[]?.name]) as $labels
| ([$pr.statusCheckRollup[]?]) as $checks
| ([$pr.files[]?.path | select(. as $f | any($globs[]; . as $g | $f | test($g | glob_re)))]) as $guarded
| [
    [($pr.state == "OPEN"),                       "PR is \($pr.state)"],
    [(any(.issueLabels[]?; . == "status:approved")), "linked issue is not status:approved"],
    [(any($labels[]; . == "needs-human") | not),  "labeled needs-human"],
    [($pr.mergeable == "MERGEABLE"),              "not mergeable (\($pr.mergeable))"],
    [($pr.mergeStateStatus == "CLEAN"),           "merge state is \($pr.mergeStateStatus), not CLEAN"],
    [($checks | length > 0),                      "no CI checks — a PR without a green check is unreviewable"],
    [($checks | all(check_ok)),                   "a check is not SUCCESS: \([$checks[] | select(check_ok | not) | (.name // .context // "?")] | join(", "))"],
    [($pr.body | has_evidence),                   "PR body has no Evidence section — nothing for a human to review"],
    [($guarded | length == 0),                    "touches HUMAN_MERGE_PATHS: \($guarded | join(", "))"]
  ]
| (map(select(.[0] | not)) | first // null) as $miss
| if $miss then "hold: \($miss[1])" else "eligible" end
