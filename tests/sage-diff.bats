#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-diff-test-$$"
  rm -rf "$SAGE_HOME"
  export TEST_REPO="$BATS_TMPDIR/sage-diff-repo-$$"
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

@test "diff: no args shows usage" {
  run "$SAGE" diff
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "diff: nonexistent agent fails" {
  run "$SAGE" diff ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "diff: non-worktree agent fails" {
  "$SAGE" create plain >/dev/null 2>&1
  run "$SAGE" diff plain
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a worktree"* ]]
}

@test "diff: shows changes in worktree" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-diff >/dev/null 2>&1
  echo "new content" > "$SAGE_HOME/agents/worker/workspace/file.txt"
  run "$SAGE" diff worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"new content"* ]]
}

@test "diff --stat shows summary" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-stat >/dev/null 2>&1
  echo "changed" > "$SAGE_HOME/agents/worker/workspace/file.txt"
  run "$SAGE" diff worker --stat
  [ "$status" -eq 0 ]
  [[ "$output" == *"file.txt"* ]]
  [[ "$output" == *"changed"* || "$output" == *"insertion"* || "$output" == *"deletion"* ]]
}

@test "diff --cached shows staged changes" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-cached >/dev/null 2>&1
  cd "$SAGE_HOME/agents/worker/workspace"
  echo "staged" > file.txt
  git add file.txt
  run "$SAGE" diff worker --cached
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged"* ]]
}

@test "diff: clean worktree shows no output" {
  cd "$TEST_REPO"
  "$SAGE" create worker --worktree feat-clean >/dev/null 2>&1
  run "$SAGE" diff worker
  [ "$status" -eq 0 ]
}
