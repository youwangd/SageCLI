#!/usr/bin/env bats
# tests/sage-ls-quiet.bats — ls -q/--quiet outputs bare agent names

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ls-quiet-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create alpha --runtime bash >/dev/null 2>&1
  "$SAGE" create bravo --runtime bash >/dev/null 2>&1
  "$SAGE" create charlie --runtime bash >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "ls -q outputs bare agent names one per line" {
  run "$SAGE" ls -q
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "alpha"
  echo "$output" | grep -qx "bravo"
  echo "$output" | grep -qx "charlie"
  ! echo "$output" | grep -qi "NAME"
  ! echo "$output" | grep -qi "RUNTIME"
}

@test "ls --quiet is same as -q" {
  run "$SAGE" ls --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "alpha"
  local count
  count=$(echo "$output" | wc -l | tr -d ' ')
  [ "$count" -eq 3 ]
}

@test "ls -q works with --running filter" {
  run "$SAGE" ls -q --running
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ls -q rejects --json and --tree" {
  run "$SAGE" ls -q --json
  [ "$status" -ne 0 ]
  run "$SAGE" ls -q --tree
  [ "$status" -ne 0 ]
}
