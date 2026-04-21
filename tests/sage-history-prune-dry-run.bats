#!/usr/bin/env bats
# tests/sage-history-prune-dry-run.bats — history --prune --dry-run previews without deleting

setup() {
  export SAGE_HOME="$(mktemp -d)"
  mkdir -p "$SAGE_HOME/agents"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_create_task() {
  local agent="$1" task_id="$2" age_seconds="$3"
  local agent_dir="$SAGE_HOME/agents/$agent"
  mkdir -p "$agent_dir/results"
  local ts=$(($(date +%s) - age_seconds))
  echo "{\"id\":\"$task_id\",\"status\":\"done\",\"queued_at\":$ts,\"started_at\":$ts,\"finished_at\":$((ts+5))}" > "$agent_dir/results/${task_id}.status.json"
  echo "result of $task_id" > "$agent_dir/results/${task_id}.result"
  echo "{\"runtime\":\"bash\"}" > "$agent_dir/runtime.json"
}

@test "history --prune --dry-run previews count without deleting" {
  _create_task "worker" "old-1" 200000
  _create_task "worker" "old-2" 200000
  _create_task "worker" "recent-1" 60
  run sage history --prune 1d --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would prune"* ]]
  [[ "$output" == *"2"* ]]
  [ -f "$SAGE_HOME/agents/worker/results/old-1.status.json" ]
  [ -f "$SAGE_HOME/agents/worker/results/old-2.status.json" ]
  [ -f "$SAGE_HOME/agents/worker/results/recent-1.status.json" ]
}

@test "history --prune --dry-run with no old tasks reports zero" {
  _create_task "worker" "fresh-1" 60
  run sage history --prune 1d --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would prune"* ]]
  [[ "$output" == *"0"* ]]
  [ -f "$SAGE_HOME/agents/worker/results/fresh-1.status.json" ]
}

@test "history --prune --dry-run --agent filters to one agent" {
  _create_task "worker" "old-w" 200000
  _create_task "tester" "old-t" 200000
  run sage history --prune 1d --dry-run --agent worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"would prune"* ]]
  [[ "$output" == *"1"* ]]
  [ -f "$SAGE_HOME/agents/worker/results/old-w.status.json" ]
  [ -f "$SAGE_HOME/agents/tester/results/old-t.status.json" ]
}
