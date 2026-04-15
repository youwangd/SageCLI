#!/usr/bin/env bats
# tests/sage-replay.bats — tests for sage replay [task-id] [--agent <name>]

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-$$"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

_create_status() {
  # $1=agent $2=task_id $3=task_text
  local dir="$SAGE_HOME/agents/$1/results"
  mkdir -p "$dir"
  printf '{"status":"done","task_text":"%s","from":"user"}\n' "$3" > "$dir/${2}.status.json"
}

@test "replay with task-id shows what would be sent (dry-run)" {
  _create_status tester task-abc "Fix the login bug"
  run sage replay task-abc --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Fix the login bug"* ]]
  [[ "$output" == *"tester"* ]]
}

@test "replay with no args uses most recent task" {
  _create_status tester task-old "old task"
  sleep 1
  _create_status tester task-new "new task"
  run sage replay --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"new task"* ]]
}

@test "replay --agent overrides target agent" {
  sage create other --runtime bash 2>/dev/null || true
  _create_status tester task-abc "Fix the login bug"
  run sage replay task-abc --agent other --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"other"* ]]
}

@test "replay with nonexistent task-id fails" {
  run sage replay nonexistent-task
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
