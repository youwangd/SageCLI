#!/usr/bin/env bats

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-history-test-$$"
  "$SAGE" init 2>/dev/null
  "$SAGE" create alpha --runtime bash 2>/dev/null
  "$SAGE" create beta --runtime bash 2>/dev/null
  local now=$(date +%s)
  local ago=$((now - 120))
  local ago2=$((now - 300))
  mkdir -p "$SAGE_HOME/agents/alpha/results"
  echo "{\"id\":\"t-001\",\"from\":\"cli\",\"status\":\"done\",\"queued_at\":$ago2,\"started_at\":$((ago2+5)),\"finished_at\":$ago}" \
    > "$SAGE_HOME/agents/alpha/results/t-001.status.json"
  echo "{\"id\":\"t-002\",\"from\":\"cli\",\"status\":\"running\",\"queued_at\":$ago,\"started_at\":$((ago+3)),\"finished_at\":null}" \
    > "$SAGE_HOME/agents/alpha/results/t-002.status.json"
  mkdir -p "$SAGE_HOME/agents/beta/results"
  echo "{\"id\":\"t-003\",\"from\":\"cli\",\"status\":\"done\",\"queued_at\":$ago,\"started_at\":$((ago+2)),\"finished_at\":$now}" \
    > "$SAGE_HOME/agents/beta/results/t-003.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "sage history shows all tasks across agents" {
  run "$SAGE" history
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
  [[ "$output" == *"t-001"* ]]
  [[ "$output" == *"t-003"* ]]
}

@test "sage history --agent filters by agent" {
  run "$SAGE" history --agent alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" != *"beta"* ]]
}

@test "sage history -n limits results" {
  run "$SAGE" history -n 1
  [ "$status" -eq 0 ]
  local count=$(echo "$output" | grep -c 't-0')
  [ "$count" -eq 1 ]
}

@test "sage history --json outputs valid JSON" {
  run "$SAGE" history --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "sage history --json contains agent and status fields" {
  run "$SAGE" history --json
  [ "$status" -eq 0 ]
  local first_agent=$(echo "$output" | jq -r '.[0].agent')
  [ -n "$first_agent" ]
  local first_status=$(echo "$output" | jq -r '.[0].status')
  [[ "$first_status" == "done" || "$first_status" == "running" ]]
}

@test "sage history shows duration for completed tasks" {
  run "$SAGE" history
  [ "$status" -eq 0 ]
  [[ "$output" == *"s"* ]]
}

@test "sage history with no tasks shows info message" {
  rm -rf "$SAGE_HOME/agents"/*/results
  run "$SAGE" history
  [ "$status" -eq 0 ]
  [[ "$output" == *"no task history"* ]]
}
