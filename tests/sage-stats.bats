#!/usr/bin/env bats
# Tests for sage stats — aggregate agent statistics

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-stats-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "stats with no agents shows zeros" {
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agents:"* ]]
  [[ "$output" == *"Tasks:"* ]]
}

@test "stats counts agents" {
  "$SAGE" create alpha >/dev/null 2>&1
  "$SAGE" create beta >/dev/null 2>&1
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
}

@test "stats counts completed tasks" {
  "$SAGE" create worker >/dev/null 2>&1
  local rdir="$SAGE_HOME/agents/worker/results"
  mkdir -p "$rdir"
  echo '{"status":"done","queued_at":1000,"started_at":1000,"finished_at":1060}' > "$rdir/t1.status.json"
  echo '{"status":"done","queued_at":2000,"started_at":2000,"finished_at":2120}' > "$rdir/t2.status.json"
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 done"* ]]
}

@test "stats counts failed tasks" {
  "$SAGE" create worker >/dev/null 2>&1
  local rdir="$SAGE_HOME/agents/worker/results"
  mkdir -p "$rdir"
  echo '{"status":"failed","queued_at":1000,"started_at":1000,"finished_at":1030}' > "$rdir/t1.status.json"
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 failed"* ]]
}

@test "stats shows total runtime" {
  "$SAGE" create worker >/dev/null 2>&1
  local rdir="$SAGE_HOME/agents/worker/results"
  mkdir -p "$rdir"
  echo '{"status":"done","queued_at":1000,"started_at":1000,"finished_at":1060}' > "$rdir/t1.status.json"
  echo '{"status":"done","queued_at":2000,"started_at":2000,"finished_at":2120}' > "$rdir/t2.status.json"
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"Runtime:"* ]]
  [[ "$output" == *"3m"* ]]
}

@test "stats shows most active agent" {
  "$SAGE" create alpha >/dev/null 2>&1
  "$SAGE" create beta >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/alpha/results" "$SAGE_HOME/agents/beta/results"
  echo '{"status":"done","queued_at":1000,"started_at":1000,"finished_at":1060}' > "$SAGE_HOME/agents/alpha/results/t1.status.json"
  echo '{"status":"done","queued_at":2000,"started_at":2000,"finished_at":2060}' > "$SAGE_HOME/agents/beta/results/t1.status.json"
  echo '{"status":"done","queued_at":3000,"started_at":3000,"finished_at":3060}' > "$SAGE_HOME/agents/beta/results/t2.status.json"
  run "$SAGE" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"beta"* ]]
}

@test "stats --json outputs valid JSON" {
  "$SAGE" create worker >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/worker/results"
  echo '{"status":"done","queued_at":1000,"started_at":1000,"finished_at":1060}' > "$SAGE_HOME/agents/worker/results/t1.status.json"
  run "$SAGE" stats --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
  [[ "$(echo "$output" | jq -r '.total_agents')" == "1" ]]
  [[ "$(echo "$output" | jq -r '.tasks_done')" == "1" ]]
}

@test "stats unknown flag errors" {
  run "$SAGE" stats --bogus
  [ "$status" -ne 0 ]
}
