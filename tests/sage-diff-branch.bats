#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-diff-branch-$$"
  rm -rf "$SAGE_HOME"
  export TEST_REPO="$BATS_TMPDIR/sage-diff-branch-repo-$$"
  rm -rf "$TEST_REPO"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "hello" > file.txt
  git add . && git commit -m "init" -q
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  cd /
  rm -rf "$SAGE_HOME" "$TEST_REPO"
}

@test "diff --branch shows committed changes vs base" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-branch >/dev/null 2>&1
  cd "$SAGE_HOME/agents/worker/workspace"
  echo "branch change" > file.txt
  git add . && git commit -m "agent edit" -q
  run "$SAGE" diff worker --branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch change"* ]]
  [[ "$output" == *"agent edit"* ]]
}

@test "diff --branch --stat shows summary" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-bstat >/dev/null 2>&1
  cd "$SAGE_HOME/agents/worker/workspace"
  echo "stat change" > file.txt
  git add . && git commit -m "stat edit" -q
  run "$SAGE" diff worker --branch --stat
  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt"* ]]
}

@test "diff --branch on clean worktree shows no diff" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-bclean >/dev/null 2>&1
  run "$SAGE" diff worker --branch
  [ "$status" -eq 0 ]
}

@test "diff --branch fails on non-worktree agent" {
  "$SAGE" create plain >/dev/null 2>&1
  run "$SAGE" diff plain --branch
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a worktree"* ]]
}
