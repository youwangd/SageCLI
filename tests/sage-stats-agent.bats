#!/usr/bin/env bats
# tests/sage-stats-agent.bats — sage stats --agent <name> filter

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$(mktemp -d)"
  sage init --force >/dev/null 2>&1
  sage create alpha --runtime bash >/dev/null 2>&1
  sage create beta --runtime bash >/dev/null 2>&1
  # Create fake completed tasks for alpha
  mkdir -p "$SAGE_HOME/agents/alpha/results"
  local now; now=$(date +%s)
  echo "{\"status\":\"done\",\"started_at\":$((now-100)),\"finished_at\":$now}" > "$SAGE_HOME/agents/alpha/results/t1.status.json"
  echo "{\"status\":\"failed\",\"started_at\":$((now-50)),\"finished_at\":$now}" > "$SAGE_HOME/agents/alpha/results/t2.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "stats --agent shows single agent stats" {
  run sage stats --agent alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 done"* ]]
  [[ "$output" == *"1 failed"* ]]
}

@test "stats --agent --json outputs JSON for single agent" {
  run sage stats --agent alpha --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tasks_done == 1'
  echo "$output" | jq -e '.tasks_failed == 1'
  echo "$output" | jq -e '.agent == "alpha"'
}

@test "stats --agent rejects nonexistent agent" {
  run sage stats --agent nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "stats --agent excludes other agents" {
  mkdir -p "$SAGE_HOME/agents/beta/results"
  echo '{"status":"done","started_at":1000,"finished_at":1100}' > "$SAGE_HOME/agents/beta/results/t1.status.json"
  run sage stats --agent alpha --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tasks_done == 1'
}
