#!/usr/bin/env bats
# tests/sage-tasks-flags.bats — sage tasks --json and --status filter

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$(mktemp -d)"
  sage init --force >/dev/null 2>&1
  sage create tester --runtime bash >/dev/null 2>&1
  # Create test task status files
  local rd="$SAGE_HOME/agents/tester/results"
  mkdir -p "$rd"
  local now=$(date +%s)
  echo "{\"id\":\"task-001\",\"status\":\"done\",\"from\":\"cli\",\"queued_at\":$((now-120)),\"started_at\":$((now-100)),\"finished_at\":$((now-10)),\"task_text\":\"fix bug\"}" > "$rd/task-001.status.json"
  echo "{\"id\":\"task-002\",\"status\":\"failed\",\"from\":\"cli\",\"queued_at\":$((now-60)),\"started_at\":$((now-50)),\"finished_at\":$((now-5)),\"task_text\":\"deploy\"}" > "$rd/task-002.status.json"
  echo "{\"id\":\"task-003\",\"status\":\"running\",\"from\":\"api\",\"queued_at\":$((now-30)),\"started_at\":$((now-20)),\"task_text\":\"test suite\"}" > "$rd/task-003.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "tasks --json outputs valid JSON array" {
  run sage tasks --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'type == "array"'
  echo "$output" | jq -e 'length == 3'
}

@test "tasks --json includes expected fields" {
  run sage tasks --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0] | has("id","agent","status","elapsed_secs","from")'
}

@test "tasks --status filters by status" {
  run sage tasks --status failed
  [ "$status" -eq 0 ]
  [[ "$output" == *"task-002"* ]]
  [[ "$output" != *"task-001"* ]]
  [[ "$output" != *"task-003"* ]]
}

@test "tasks --status --json combines both flags" {
  run sage tasks --status done --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1'
  echo "$output" | jq -e '.[0].status == "done"'
}

@test "tasks --status rejects invalid status" {
  run sage tasks --status bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid status"* ]]
}
