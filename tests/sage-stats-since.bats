#!/usr/bin/env bats
# tests/sage-stats-since.bats — sage stats --since <duration> filter

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-stats-since-$$"
  mkdir -p "$SAGE_HOME"
  ./sage init --force >/dev/null 2>&1
  # Create agent with tasks at known timestamps
  ./sage create tester --runtime bash >/dev/null 2>&1
  local results_dir="$SAGE_HOME/agents/tester/results"
  mkdir -p "$results_dir"
  local now; now=$(date +%s)
  # Task completed 30 minutes ago
  local t1=$((now - 1800))
  printf '{"status":"done","started_at":%d,"finished_at":%d}\n' "$t1" "$((t1 + 60))" > "$results_dir/task-recent.status.json"
  # Task completed 2 days ago
  local t2=$((now - 172800))
  printf '{"status":"done","started_at":%d,"finished_at":%d}\n' "$t2" "$((t2 + 120))" > "$results_dir/task-old.status.json"
  # Failed task 1 hour ago
  local t3=$((now - 3600))
  printf '{"status":"failed","started_at":%d,"finished_at":%d}\n' "$t3" "$((t3 + 30))" > "$results_dir/task-fail.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "stats --since 1h shows only recent tasks" {
  run ./sage stats --since 1h
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1 done"* ]]
  [[ "$output" != *"2 done"* ]]
}

@test "stats --since 1d includes tasks from last 24h" {
  run ./sage stats --since 1d
  [[ "$status" -eq 0 ]]
  # Should include recent (30m ago) + failed (1h ago) but not old (2d ago)
  [[ "$output" == *"1 done"* ]]
  [[ "$output" == *"1 failed"* ]]
}

@test "stats --since --json outputs filtered JSON" {
  run ./sage stats --since 1h --json
  [[ "$status" -eq 0 ]]
  local done_count; done_count=$(echo "$output" | jq '.tasks_done')
  [[ "$done_count" -eq 1 ]]
}

@test "stats --since --agent combines both filters" {
  run ./sage stats --since 1h --agent tester --json
  [[ "$status" -eq 0 ]]
  local done_count; done_count=$(echo "$output" | jq '.tasks_done')
  [[ "$done_count" -eq 1 ]]
  [[ "$output" == *"tester"* ]]
}

@test "stats --since rejects invalid duration" {
  run ./sage stats --since abc
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid duration"* ]]
}
