#!/usr/bin/env bats
# tests/sage-diff-all.bats — diff --all shows changes across all worktree agents

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-diff-all-$$"
  rm -rf "$SAGE_HOME"
  export TEST_REPO="$BATS_TMPDIR/sage-diff-all-repo-$$"
  rm -rf "$TEST_REPO"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "base" > file.txt
  git add . && git commit -m "init" -q
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create wt1 --runtime bash --worktree wt1-branch >/dev/null 2>&1
  "$SAGE" create wt2 --runtime bash --worktree wt2-branch >/dev/null 2>&1
  "$SAGE" create plain --runtime bash >/dev/null 2>&1
  # Make changes in wt1
  local ws1="$SAGE_HOME/agents/wt1/workspace"
  echo "changed by wt1" > "$ws1/file.txt"
}

teardown() {
  "$SAGE" stop --all >/dev/null 2>&1 || true
  cd /
  rm -rf "$SAGE_HOME" "$TEST_REPO"
}

@test "diff --all shows changes from worktree agents with headers" {
  local out
  out=$("$SAGE" diff --all)
  echo "$out" | grep -q "wt1"
  echo "$out" | grep -q "changed by wt1"
}

@test "diff --all --stat shows stat summary" {
  local out
  out=$("$SAGE" diff --all --stat)
  echo "$out" | grep -q "wt1"
  echo "$out" | grep -q "file.txt"
}

@test "diff --all skips non-worktree agents" {
  local out
  out=$("$SAGE" diff --all 2>&1) || true
  ! echo "$out" | grep -q "plain"
}

@test "diff --all rejects agent name argument" {
  run "$SAGE" diff --all wt1
  [ "$status" -ne 0 ]
}
