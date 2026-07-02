#!/usr/bin/env bash
# YOLO git-acceptance harness — objective, AI-free validation of the derivation rules in
# .claude/yolo/conventions.md. Each case builds a throwaway repo, runs the EXACT git
# commands the conventions specify, and asserts the classification. Where a fix changed a
# rule, the case asserts the OLD rule was wrong (red) and the NEW rule is right (green).
#
# Usage: bash docs/validation/git-acceptance/run.sh
# Exit:  0 = all green, 1 = a regression/assertion failed.
set -u

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
# assert "label" expected actual
assert(){ if [ "$2" = "$3" ]; then ok "$1 (= $3)"; else bad "$1 (expected '$2', got '$3')"; fi; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/yolo-accept.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
GIT_CFG=(-c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false -c advice.detachedHead=false)
g(){ git "${GIT_CFG[@]}" "$@"; }

newrepo(){ # $1 dir
  rm -rf "$1"; mkdir -p "$1"; ( cd "$1" && g init -q && g commit -q --allow-empty -m "root" ); }

# ---- reference implementations of the two derivation rule-sets (mirroring conventions.md) ----
# Args: repo slug base  -> echoes planned|in-progress|done
new_status(){ ( cd "$1"; slug=$2; base=$3
  br="feature/$slug"; have_br=$(g rev-parse --verify -q "$br" >/dev/null 2>&1 && echo 1 || echo 0)
  # durable done signals (survive branch deletion / squash)
  g rev-parse --verify -q "refs/tags/yolo/done/$slug" >/dev/null 2>&1 && { echo done; return; }
  g log "$base" --format='%(trailers:key=YOLO-Feature,valueonly)' 2>/dev/null | sed '/^$/d' | grep -qx "$slug" && { echo done; return; }
  # NOTE: git branch --merged is intentionally NOT used (false-positives an empty branch).
  if [ "$have_br" = 1 ]; then
    # verified-but-not-yet-landed: TIP commit carries the trailer AND verification.md is committed — see F8/F9.
    if g log -1 "$br" --format='%(trailers:key=YOLO-Verified,valueonly)' 2>/dev/null | grep -qx true \
       && g cat-file -e "$br:workspace/features/$slug/verification.md" 2>/dev/null; then echo done; return; fi
    echo in-progress; return
  fi
  echo planned ); }

old_status(){ ( cd "$1"; slug=$2; base=$3   # pre-fix rules (branch-scoped evidence only)
  br="feature/$slug"; have_br=$(g rev-parse --verify -q "$br" >/dev/null 2>&1 && echo 1 || echo 0)
  if [ "$have_br" = 1 ]; then
    g branch --merged "$base" 2>/dev/null | sed 's/^[* ] *//' | grep -qx "$br" && { echo done; return; }
    g log "$base..$br" --format='%(trailers:key=YOLO-Verified,valueonly)' 2>/dev/null | grep -qx true && { echo done; return; }
    echo in-progress; return
  fi
  echo planned ); }

# helper: take a feature from brief through verified on its own branch
build_feature(){ ( cd "$1"; slug=$2; base=$3
  g switch -q -c "feature/$slug" "$base"
  echo "feat" > "$slug.txt"; g add .; g commit -q -m "implement $slug" --trailer "YOLO-Task: do-$slug"
  mkdir -p "workspace/features/$slug"; echo "v" > "workspace/features/$slug/verification.md"
  g add .; g commit -q -m "yolo: verify $slug" --trailer "YOLO-Verified: true" ); }

# land a feature: merge with the durable markers (the FIX), then delete the branch
land_merge(){ ( cd "$1"; slug=$2; base=$3
  g switch -q "$base"
  g merge -q --no-ff "feature/$slug" -m "yolo: merge feature/$slug" -m "YOLO-Feature: $slug"
  g tag -a "yolo/done/$slug" -m "yolo: done $slug"
  g worktree remove "../wt-$slug" 2>/dev/null || true
  g branch -q -D "feature/$slug" ); }

echo "== F1/F2: shipped feature whose branch was deleted =="
R="$ROOT/r1"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/foo; echo brief>workspace/features/foo/brief.md; g add .; g commit -q -m "yolo: brief foo" )
build_feature "$R" foo main
land_merge "$R" foo main
assert "OLD rule misreports shipped+deleted as planned (the bug)" planned "$(old_status "$R" foo main)"
assert "NEW rule reports shipped+deleted as done"                  done    "$(new_status "$R" foo main)"

echo "== F2: squash-merged + branch deleted (YOLO-Verified trailer NOT on base) =="
R="$ROOT/r2"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/sq; echo brief>workspace/features/sq/brief.md; g add .; g commit -q -m "yolo: brief sq" )
build_feature "$R" sq main
( cd "$R"; g switch -q main; g merge -q --squash "feature/sq"; g commit -q -m "yolo: merge feature/sq" -m "YOLO-Feature: sq"; g tag -a "yolo/done/sq" -m d; g branch -q -D "feature/sq" )
assert "squash: base history has NO YOLO-Verified trailer" "" "$(cd "$R"; g log main --format='%(trailers:key=YOLO-Verified,valueonly)' | sed '/^$/d')"
assert "OLD rule misreports squash+deleted as planned"  planned "$(old_status "$R" sq main)"
assert "NEW rule reports squash+deleted as done (via YOLO-Feature + tag)" done "$(new_status "$R" sq main)"

echo "== in-progress / planned / verified-not-landed =="
R="$ROOT/r3"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/{ip,pl,vr}; for s in ip pl vr; do echo b>workspace/features/$s/brief.md; done; g add .; g commit -q -m "yolo: briefs" )
( cd "$R"; g switch -q -c feature/ip main; echo x>ip.txt; g add .; g commit -q -m wip --trailer "YOLO-Task: t1"; g switch -q main )
build_feature "$R" vr main; ( cd "$R"; g switch -q main )  # vr verified but never merged, branch kept
assert "branch + tasks, unverified -> in-progress" in-progress "$(new_status "$R" ip main)"
assert "brief only, no branch -> planned"          planned     "$(new_status "$R" pl main)"
assert "verified branch, not yet landed -> done"   done        "$(new_status "$R" vr main)"

echo "== F4 (red-team regression): freshly-cut empty branch must NOT read as done =="
R="$ROOT/r3b"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/fresh; echo b>workspace/features/fresh/brief.md; g add .; g commit -q -m "yolo: brief fresh"
  g switch -q -c feature/fresh main; g switch -q main )   # branch cut, zero own-commits (tip == base)
assert "empty branch via OLD branch--merged rule WOULD be done (the trap)" done "$(old_status "$R" fresh main)"
assert "empty branch via NEW rule is in-progress, not done"               in-progress "$(new_status "$R" fresh main)"

echo "== F3: two-dot vs three-dot diff when base advances =="
R="$ROOT/r4"; newrepo "$R"
( cd "$R"; g switch -q -c feature/bar main; printf 'one line\n' > feat.txt; g add .; g commit -q -m "add 1 line"
  g switch -q main; printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n' > unrelated.txt; g add .; g commit -q -m "10 unrelated lines on base" )
two=$(cd "$R"; g diff main..feature/bar --shortstat)
three=$(cd "$R"; g diff main...feature/bar --shortstat)
echo "    two-dot : $two"
echo "    three-dot: $three"
if echo "$two" | grep -q 'deletion'; then ok "two-dot folds in base changes (deletions) -> inflated/wrong"; else bad "expected two-dot to show spurious deletions"; fi
if echo "$three" | grep -q 'deletion'; then bad "three-dot should show NO deletions"; else ok "three-dot shows only what the branch added (1 file, no deletions)"; fi

echo "== F5: task-trailer count must dedup by id =="
R="$ROOT/r5"; newrepo "$R"
( cd "$R"; g switch -q -c feature/multi main
  for i in 1 2 3; do echo "$i">>m.txt; g add .; g commit -q -m "step $i of one task" --trailer "YOLO-Task: big-task"; done )
raw=$(cd "$R"; g log main..feature/multi --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d' | wc -l | tr -d ' ')
ded=$(cd "$R"; g log main..feature/multi --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d' | sort -u | wc -l | tr -d ' ')
assert "raw trailer count over-counts one task spanning 3 commits" 3 "$raw"
assert "deduped count is correct (1 distinct task id)"            1 "$ded"

echo "== F6: base_branch detection prefers origin/HEAD over main/master =="
R="$ROOT/r6"; newrepo "$R"
( cd "$R"; g switch -q -c develop; g switch -q main
  # simulate a remote whose default branch is 'develop'
  g update-ref refs/remotes/origin/develop refs/heads/develop
  g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop )
det=$(cd "$R"; g symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
assert "detection resolves the real default branch, not 'main'" develop "$det"

echo "== F7: worktree must be removed BEFORE deleting its branch =="
R="$ROOT/r7"; newrepo "$R"
( cd "$R"; g switch -q -c feature/iso main; g switch -q main; g worktree add -q "../wt-iso" feature/iso ) 2>/dev/null
del_while_present=$(cd "$R"; g branch -D feature/iso >/dev/null 2>&1; echo $?)
( cd "$R"; g worktree remove "../wt-iso" )
del_after_remove=$(cd "$R"; g branch -D feature/iso >/dev/null 2>&1; echo $?)
assert "deleting a worktree-checked-out branch FAILS (nonzero)" 1 "$del_while_present"
assert "deleting it AFTER worktree removal SUCCEEDS"            0 "$del_after_remove"

echo "== F8: verified-then-reworked branch — range scan false-positives 'done'; tip check is correct =="
R="$ROOT/r8"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/rew; echo b>workspace/features/rew/brief.md; g add .; g commit -q -m "yolo: brief rew" )
build_feature "$R" rew main                                   # ends at the YOLO-Verified commit (tip)
( cd "$R"; g switch -q feature/rew; echo more >> rew.txt; g add .; g commit -q -m "more work after verify"; g switch -q main )  # tip no longer carries the trailer
range=$(cd "$R"; g log main..feature/rew --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo done || echo in-progress)
tip=$(cd "$R";   g log -1 feature/rew     --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo done || echo in-progress)
assert "OLD range scan misreads reworked-after-verify branch as done (the bug)" done "$range"
assert "NEW tip check reports in-progress (verification is stale)"              in-progress "$tip"
assert "NEW reference rule (now tip-based) agrees: in-progress, not done"       in-progress "$(new_status "$R" rew main)"

echo "== F9: a YOLO-Verified trailer WITHOUT a committed verification.md must NOT read as done =="
R="$ROOT/r9"; newrepo "$R"
( cd "$R"; mkdir -p workspace/features/notrail; echo b>workspace/features/notrail/brief.md; g add .; g commit -q -m "yolo: brief notrail" )
# trailer hand-added to the tip, but NO verification.md committed under the feature folder
( cd "$R"; g switch -q -c feature/notrail main; echo code>impl.txt; g add .; g commit -q -m "work" --trailer "YOLO-Verified: true"; g switch -q main )
assert "trailer is present on the tip"                          true "$(cd "$R"; g log -1 feature/notrail --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo true || echo false)"
assert "but no committed verification.md exists"               false "$(cd "$R"; g cat-file -e 'feature/notrail:workspace/features/notrail/verification.md' 2>/dev/null && echo true || echo false)"
assert "trailer-only WOULD read done (the over-trust bug)"      done "$(cd "$R"; g log -1 feature/notrail --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo done || echo in-progress)"
assert "NEW rule (trailer AND verification.md) reports in-progress, not done" in-progress "$(new_status "$R" notrail main)"

echo "== F10: PR-path done-trailer must be the FINAL paragraph — prose after it silently fails to parse =="
R="$ROOT/r10"; newrepo "$R"
( cd "$R"; g switch -q -c feature/place main; echo c>impl.txt; g add .; g commit -q -m "work"; g switch -q main )
# the durable-done probe yolo-status runs against base history (conventions.md): YOLO-Feature trailer
probe10(){ cd "$R"; g log -1 main --format='%(trailers:key=YOLO-Feature,valueonly)' | sed '/^$/d' | grep -qx place && echo done || echo not-found; }
# the FIX (yolo-finish *Land*): trailer alone as the final paragraph -> parses
( cd "$R"; g merge -q --no-ff feature/place -m "yolo: merge feature/place" -m "YOLO-Feature: place" )
assert "trailer as the final standalone paragraph parses (the correct form)" done "$(probe10)"
( cd "$R"; g reset -q --hard HEAD~1 )
# the TRAP (Finding 1): a rich PR body with a summary section AFTER the trailer -> does NOT parse
( cd "$R"; g merge -q --no-ff feature/place -m "yolo: merge feature/place" -m "YOLO-Feature: place" -m "## Verification
all criteria passed" )
assert "prose paragraph AFTER the trailer defeats the probe (the bug the doc now warns against)" not-found "$(probe10)"

echo
echo "==================  $PASS passed, $FAIL failed  =================="
[ "$FAIL" -eq 0 ]
