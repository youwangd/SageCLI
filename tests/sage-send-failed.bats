#!/usr/bin/env bats
# tests/sage-send-failed.bats — send --failed broadcasts to agents whose latest task failed

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-send-failed-$$"
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

@test "send --failed requires --headless" {
  run "$SAGE" send --failed "retry"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "headless"
}

@test "send --failed rejects --then" {
  run "$SAGE" send --failed --headless --then bravo "retry"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "then"
}

@test "send --failed with no failed agents prints warning" {
  # No tasks have been run, so no agent has a failed latest task
  run "$SAGE" send --failed --headless "retry"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "no failed"
}
