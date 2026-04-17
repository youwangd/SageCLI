#!/usr/bin/env bats
# tests/sage-send-all.bats — send --all broadcasts to all running agents

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-send-all-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create alpha --runtime bash >/dev/null 2>&1
  "$SAGE" create bravo --runtime bash >/dev/null 2>&1
}

teardown() {
  "$SAGE" stop alpha 2>/dev/null || true
  "$SAGE" stop bravo 2>/dev/null || true
  rm -rf "$SAGE_HOME"
}

@test "send --all requires --headless" {
  run "$SAGE" send --all "hello"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "headless"
}

@test "send --all rejects --then" {
  run "$SAGE" send --all --headless --then bravo "hello"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "then"
}

@test "send --all with no running agents prints warning" {
  run "$SAGE" send --all --headless "hello"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no running agents"
}

@test "send --all skips agent name positional arg" {
  run "$SAGE" send --all --headless "checkpoint now"
  [ "$status" -eq 0 ]
  # Should not complain about missing agent name
  ! echo "$output" | grep -qi "usage:"
}
