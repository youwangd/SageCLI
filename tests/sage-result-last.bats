#!/usr/bin/env bats
# tests/sage-result-last.bats — tests for sage result (no args) showing most recent task

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-$$"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init 2>/dev/null || true
  sage create tester --runtime bash 2>/dev/null || true
}

_create_task_result() {
  # $1=agent $2=task_id $3=status $4=output
  local dir="$SAGE_HOME/agents/$1/results"
  mkdir -p "$dir"
  printf '{"status":"%s"}\n' "$3" > "$dir/${2}.status.json"
  printf '{"output":"%s"}\n' "$4" > "$dir/${2}.result.json"
}

@test "result with no args shows most recent task" {
  _create_task_result tester task-old done "old result"
  sleep 1
  _create_task_result tester task-new done "new result"
  run sage result
  [ "$status" -eq 0 ]
  [[ "$output" == *"new result"* ]]
}

@test "result with no args when no tasks exist shows error" {
  run sage result
  [ "$status" -ne 0 ]
  [[ "$output" == *"no task"* ]] || [[ "$output" == *"No task"* ]]
}

@test "result with task-id still works (backward compat)" {
  _create_task_result tester task-123 done "specific result"
  run sage result task-123
  [ "$status" -eq 0 ]
  [[ "$output" == *"specific result"* ]]
}

@test "result with no args picks across multiple agents" {
  sage create other --runtime bash 2>/dev/null || true
  _create_task_result tester task-a done "tester result"
  sleep 1
  _create_task_result other task-b done "other result"
  run sage result
  [ "$status" -eq 0 ]
  [[ "$output" == *"other result"* ]]
}
