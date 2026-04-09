#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-cmd2-test-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# --- tool ---

@test "tool with no subcommand fails" {
  run "$SAGE" tool
  [ "$status" -ne 0 ]
}

@test "tool add registers a tool" {
  echo '#!/bin/bash' > "$BATS_TMPDIR/mytool.sh"
  run "$SAGE" tool add mytool "$BATS_TMPDIR/mytool.sh"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/tools/mytool.sh" ]
}

@test "tool ls lists registered tools" {
  echo '#!/bin/bash' > "$BATS_TMPDIR/mytool.sh"
  "$SAGE" tool add mytool "$BATS_TMPDIR/mytool.sh"
  run "$SAGE" tool ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"mytool"* ]]
}

@test "tool add with missing args fails" {
  run "$SAGE" tool add
  [ "$status" -ne 0 ]
}

# --- tasks ---

@test "tasks with no agents shows header" {
  run "$SAGE" tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tasks"* ]]
}

@test "tasks for nonexistent agent fails" {
  run "$SAGE" tasks ghost
  [ "$status" -ne 0 ]
}

# --- result ---

@test "result with no task-id fails" {
  run "$SAGE" result
  [ "$status" -ne 0 ]
}

@test "result with nonexistent task-id fails" {
  run "$SAGE" result fake-task-999
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# --- call validation ---

@test "call with no args fails" {
  run "$SAGE" call
  [ "$status" -ne 0 ]
}

@test "call with only agent name fails" {
  run "$SAGE" call someagent
  [ "$status" -ne 0 ]
}

# --- logs ---

@test "logs with no name fails" {
  run "$SAGE" logs
  [ "$status" -ne 0 ]
}

@test "logs for agent with no log file fails" {
  run "$SAGE" logs noagent
  [ "$status" -ne 0 ]
}

@test "logs --clear creates empty log" {
  "$SAGE" create worker1
  mkdir -p "$SAGE_HOME/logs"
  echo "some log" > "$SAGE_HOME/logs/worker1.log"
  run "$SAGE" logs worker1 --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
}

# --- trace ---

@test "trace with no data shows message" {
  run "$SAGE" trace
  [ "$status" -eq 0 ]
  [[ "$output" == *"no trace"* ]]
}

@test "trace --clear succeeds" {
  run "$SAGE" trace --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
}
