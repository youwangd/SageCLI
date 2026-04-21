#!/usr/bin/env bats
# tests/sage-history-count.bats — history --count prints plain integer of matching entries

setup() {
  export SAGE_HOME="$(mktemp -d)"
  mkdir -p "$SAGE_HOME/agents"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_create_task() {
  local agent="$1" task_id="$2" age_seconds="$3" status="${4:-done}"
  local agent_dir="$SAGE_HOME/agents/$agent"
  mkdir -p "$agent_dir/results"
  local ts=$(($(date +%s) - age_seconds))
  echo "{\"id\":\"$task_id\",\"status\":\"$status\",\"queued_at\":$ts,\"started_at\":$ts,\"finished_at\":$((ts+5)),\"task_text\":\"task $task_id\"}" > "$agent_dir/results/${task_id}.status.json"
  echo "{\"runtime\":\"bash\"}" > "$agent_dir/runtime.json"
}

@test "history --count prints 0 when no history" {
  run sage history --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "history --count prints integer matching entry count" {
  _create_task "worker" "t1" 60
  _create_task "worker" "t2" 120
  _create_task "tester" "t3" 180
  run sage history --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "history --count honors --agent filter" {
  _create_task "worker" "t1" 60
  _create_task "worker" "t2" 120
  _create_task "tester" "t3" 180
  run sage history --count --agent worker
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}
