#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-lifecycle-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- start ---

@test "start fails for nonexistent agent" {
  run "$SAGE" start nonexistent
  [ "$status" -ne 0 ]
}

@test "start with no args and no agents does not crash" {
  run "$SAGE" start
  # May fail due to tmux not available, but should not crash with unbound var
  [[ "$output" != *"unbound variable"* ]]
}

@test "start --all with no agents does not crash" {
  run "$SAGE" start --all
  [[ "$output" != *"unbound variable"* ]]
}

# --- stop ---

@test "stop fails for nonexistent agent" {
  run "$SAGE" stop nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "stop named agent that is not running shows info" {
  "$SAGE" create myagent
  run "$SAGE" stop myagent
  # stop_agent for non-running agent outputs "not running" info
  [[ "$output" == *"not running"* ]]
}

@test "stop with no args does not crash" {
  run "$SAGE" stop
  [[ "$output" != *"unbound variable"* ]]
}

@test "stop --all with no agents does not crash" {
  run "$SAGE" stop --all
  [[ "$output" != *"unbound variable"* ]]
}

# --- restart ---

@test "restart requires a name" {
  run "$SAGE" restart
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "restart fails for nonexistent agent" {
  run "$SAGE" restart nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
