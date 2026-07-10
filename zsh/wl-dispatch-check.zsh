#!/usr/bin/env zsh
# Headless dispatch check for the wl() launcher function (defined in ./zshrc).
# Extracts wl(), stubs the bin scripts (via WLAUNCH_BIN_DIR) and the launch tools
# (on PATH), and asserts: parse -> dir resolution -> cd -> tool launch, for every
# kind x tool, creating no real worktrees. Run: `zsh zsh/wl-dispatch-check.zsh`.
emulate -L zsh
set -u

SRC="${0:A:h}/zshrc"
FN="$(mktemp)"
awk '
  /^wl\(\) \{/ { in_fn=1; depth=0 }
  in_fn {
    print
    depth += gsub(/\{/, "{")
    depth -= gsub(/\}/, "}")
    if (depth == 0) exit
  }
' "$SRC" > "$FN"

grep -q '^wl() {' "$FN" && [[ "$(grep -c '^}' "$FN")" -eq 1 ]] || { print "FAIL: could not extract wl()"; exit 1 }
zsh -n "$FN" || { print "FAIL: wl() syntax error"; exit 1 }
print "ok: wl() extracted and parses cleanly"

ROOT="$(mktemp -d)"
BIN="$ROOT/bin"; REPO="$ROOT/repo"; PLAIN="$ROOT/plain"; WT="$ROOT/wt"; REC="$ROOT/rec"
mkdir -p "$BIN" "$REPO" "$PLAIN" "$WT" "$ROOT/from-pr" "$ROOT/from-setup" "$ROOT/from-canonical"
git -C "$REPO" init -q

cat > "$BIN/wlaunch" <<'EOF'
#!/bin/sh
[ -n "${WL_TEST_FAIL:-}" ] && exit 1
printf '%s\n' "$WL_TEST_LINE"
EOF
cat > "$BIN/pr-worktree.sh" <<EOF
#!/bin/sh
[ -n "\${WL_PR_FAIL:-}" ] && exit 2
printf '%s\n' "$ROOT/from-pr"
EOF
cat > "$BIN/worktree-setup.sh" <<EOF
#!/bin/sh
printf 'SETUP ARGS:%s\n' "\$*" >> "$REC"
printf '%s\n' "$ROOT/from-setup"
EOF
cat > "$BIN/canonical-checkout.sh" <<EOF
#!/bin/sh
[ -n "\${WL_CANONICAL_FAIL:-}" ] && exit 3
printf 'CANONICAL:%s\n' "\$*" >> "$REC"
printf '%s\n' "$ROOT/from-canonical"
EOF
for t in claude codex lazygit serie; do
cat > "$BIN/$t" <<EOF
#!/bin/sh
pwd >> "$REC"
printf 'TOOL:%s ARGS:%s\n' "$t" "\$*" >> "$REC"
EOF
done
chmod +x "$BIN"/*

export WLAUNCH_BIN_DIR="$BIN" PATH="$BIN:$PATH"
T=$'\t'
fails=0

check() { # desc  line  expect_pwd  [rec_substr]
  local desc="$1" line="$2" exp="$3" recsub="${4:-}"
  : > "$REC"
  local out
  out="$(WL_TEST_LINE="$line" zsh -c "source '$FN'; wl >/dev/null 2>&1; pwd")"
  local ok=1
  [[ "$out" == "$exp" ]] || ok=0
  [[ -z "$recsub" ]] || grep -q -- "$recsub" "$REC" || ok=0
  if (( ok )); then print "PASS: $desc"; else
    print "FAIL: $desc"; print "      pwd=$out want=$exp rec=[$(tr '\n' '|' <"$REC")]"; (( fails++ ))
  fi
}

check "worktree+shell  -> cd ref, no launch"             "v1${T}worktree${T}${REPO}${T}${WT}${T}shell" "$WT"
check "repo+lazygit    -> reconcile primary checkout"   "v1${T}repo${T}${REPO}${T}${T}lazygit"        "$ROOT/from-canonical" "CANONICAL:$REPO"
check "plain+shell     -> cd path without reconciliation" "v1${T}repo${T}${PLAIN}${T}${T}shell"           "$PLAIN"
check "pr+serie        -> pr-worktree.sh, serie -i head" "v1${T}pr${T}${REPO}${T}123${T}serie"         "$ROOT/from-pr" "ARGS:--initial-selection head"
check "branch+shell    -> worktree-setup.sh, empty base" "v1${T}branch${T}${REPO}${T}feat/x${T}shell"             "$ROOT/from-setup" "SETUP ARGS:feat/x"
check "branch+base      -> worktree-setup.sh fwds base"  "v1${T}branch${T}${REPO}${T}feat/x${T}shell${T}origin/dev" "$ROOT/from-setup" "SETUP ARGS:feat/x origin/dev"
# claude arms the auto-submit flag (it runs as a real command at the next prompt, not
# inline); verify the cd landed AND _WL_AUTOSUBMIT was set.
armed="$(WL_TEST_LINE="v1${T}repo${T}${REPO}${T}${T}claude" zsh -c "source '$FN'; wl >/dev/null 2>&1; print -r -- \"\$PWD|\$_WL_AUTOSUBMIT\"")"
if [[ "$armed" == "$ROOT/from-canonical|claude" ]]; then
  print "PASS: claude (armed)   -> reconcile repo + _WL_AUTOSUBMIT=claude"
else
  print "FAIL: claude arm = $armed  want $ROOT/from-canonical|claude"; (( fails++ ))
fi
codex_armed="$(WL_TEST_LINE="v1${T}repo${T}${REPO}${T}${T}codex" zsh -c "source '$FN'; wl >/dev/null 2>&1; print -r -- \"\$PWD|\$_WL_AUTOSUBMIT\"")"
if [[ "$codex_armed" == "$ROOT/from-canonical|codex" ]]; then
  print "PASS: codex (armed)    -> reconcile repo + _WL_AUTOSUBMIT=codex"
else
  print "FAIL: codex arm = $codex_armed  want $ROOT/from-canonical|codex"; (( fails++ ))
fi

canonical_fail="$(WL_CANONICAL_FAIL=1 WL_TEST_LINE="v1${T}repo${T}${REPO}${T}${T}shell" zsh -c "cd '$ROOT'; source '$FN'; wl >/dev/null 2>&1; pwd")"
if [[ "$canonical_fail" == "$ROOT" ]]; then print "PASS: canonical failure -> no cd"; else print "FAIL: canonical failure changed dir to $canonical_fail"; (( fails++ )); fi

cancel_out="$(WL_TEST_FAIL=1 zsh -c "cd '$ROOT'; source '$FN'; wl >/dev/null 2>&1; pwd")"
if [[ "$cancel_out" == "$ROOT" ]]; then print "PASS: cancel -> no cd, no launch"; else print "FAIL: cancel changed dir to $cancel_out"; (( fails++ )); fi

pr_fail="$(WL_PR_FAIL=1 WL_TEST_LINE="v1${T}pr${T}${REPO}${T}123${T}shell" zsh -c "cd '$ROOT'; source '$FN'; wl >/dev/null 2>&1; pwd")"
if [[ "$pr_fail" == "$ROOT" ]]; then print "PASS: PR helper failure -> no cd"; else print "FAIL: PR helper failure changed dir to $pr_fail"; (( fails++ )); fi

print ""
(( fails )) && { print "RESULT: $fails failure(s)"; exit 1 } || print "RESULT: all dispatch cases pass"
