#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-cmd-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- ls ---

@test "ls with no agents shows nothing" {
  run "$SAGE" ls
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ls lists created agents" {
  "$SAGE" create alpha
  "$SAGE" create beta
  run "$SAGE" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "ls hides dotfile directories" {
  "$SAGE" create visible
  mkdir -p "$SAGE_HOME/agents/.hidden"
  run "$SAGE" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"visible"* ]]
  [[ "$output" != *".hidden"* ]]
}

# --- clean ---

@test "clean succeeds with no stale files" {
  run "$SAGE" clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleaned"* ]]
}

@test "clean removes stale pid files" {
  "$SAGE" create worker1
  echo "99999999" > "$SAGE_HOME/agents/worker1/.pid"
  [ -f "$SAGE_HOME/agents/worker1/.pid" ]
  run "$SAGE" clean
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/worker1/.pid" ]
}

# --- status ---

@test "status with no agents shows no agents message" {
  run "$SAGE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"no agents"* ]]
}

@test "status shows created agent as stopped" {
  "$SAGE" create myagent
  run "$SAGE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"myagent"* ]]
  [[ "$output" == *"stopped"* ]]
}

@test "status shows SAGE header" {
  run "$SAGE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"SAGE"* ]]
}

# --- inbox ---

@test "inbox with no messages produces no error" {
  run "$SAGE" inbox
  [ "$status" -eq 0 ]
}

@test "inbox --clear with no messages succeeds" {
  run "$SAGE" inbox --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
}

@test "inbox --json with no messages produces no error" {
  run "$SAGE" inbox --json
  [ "$status" -eq 0 ]
}

# --- send validation ---

@test "send with no args fails" {
  run "$SAGE" send
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "send to nonexistent agent fails" {
  run "$SAGE" send ghost "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
