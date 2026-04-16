#!/usr/bin/env bats
# tests/sage-history-prune.bats — history --prune deletes old task history

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

@test "history --prune removes tasks older than duration" {
  _create_task "worker" "old-1" 90000    # ~25 hours old
  _create_task "worker" "recent-1" 3000  # ~50 min old
  run sage history --prune 1d
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]  # pruned 1 task
  [ ! -f "$SAGE_HOME/agents/worker/results/old-1.status.json" ]
  [ -f "$SAGE_HOME/agents/worker/results/recent-1.status.json" ]
}

@test "history --prune removes result files alongside status files" {
  _create_task "worker" "old-2" 200000  # ~2.3 days old
  run sage history --prune 1d
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/worker/results/old-2.result" ]
}

@test "history --prune --agent filters to one agent" {
  _create_task "worker" "old-w" 200000
  _create_task "tester" "old-t" 200000
  run sage history --prune 1d --agent worker
  [ "$status" -eq 0 ]
  [ ! -f "$SAGE_HOME/agents/worker/results/old-w.status.json" ]
  [ -f "$SAGE_HOME/agents/tester/results/old-t.status.json" ]
}

@test "history --prune with no old tasks reports zero" {
  _create_task "worker" "fresh-1" 60  # 1 min old
  run sage history --prune 1d
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
  [ -f "$SAGE_HOME/agents/worker/results/fresh-1.status.json" ]
}
