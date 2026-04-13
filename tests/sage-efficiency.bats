#!/usr/bin/env bats
# Tests for sage stats --efficiency — tasks completed per dollar

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-eff-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

_add_done_task() {
  local agent="$1" id="$2"
  mkdir -p "$SAGE_HOME/agents/$agent/results"
  cat > "$SAGE_HOME/agents/$agent/results/${id}.status.json" <<EOF
{"id":"$id","status":"done","queued_at":1000,"started_at":1001,"finished_at":1010}
EOF
}

@test "stats --efficiency with no agents shows header" {
  run "$SAGE" stats --efficiency
  [ "$status" -eq 0 ]
  [[ "$output" == *"Efficiency"* ]]
}

@test "stats --efficiency calculates tasks per dollar" {
  "$SAGE" create alpha --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  _add_done_task alpha t1
  _add_done_task alpha t2
  run "$SAGE" stats --efficiency --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
  [[ "$(echo "$output" | jq -r '.agents[0].name')" == "alpha" ]]
  [[ "$(echo "$output" | jq '.agents[0].completed_tasks')" == "2" ]]
  [[ "$(echo "$output" | jq '.agents[0].tasks_per_dollar')" != "null" ]]
}

@test "stats --efficiency shows N/A for zero-cost agents" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  echo '{"ts":1000,"input":1000,"output":500}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  _add_done_task worker t1
  run "$SAGE" stats --efficiency
  [ "$status" -eq 0 ]
  [[ "$output" == *"N/A"* ]]
}

@test "stats --efficiency --json zero cost gives null tasks_per_dollar" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  echo '{"ts":1000,"input":1000,"output":500}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  _add_done_task worker t1
  run "$SAGE" stats --efficiency --json
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq '.agents[0].tasks_per_dollar')" == "null" ]]
  [[ "$(echo "$output" | jq '.agents[0].completed_tasks')" == "1" ]]
}

@test "stats --efficiency only counts done tasks not failed" {
  "$SAGE" create alpha --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  _add_done_task alpha t1
  mkdir -p "$SAGE_HOME/agents/alpha/results"
  echo '{"id":"t2","status":"failed","queued_at":1000}' > "$SAGE_HOME/agents/alpha/results/t2.status.json"
  run "$SAGE" stats --efficiency --json
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq '.agents[0].completed_tasks')" == "1" ]]
}

@test "stats --efficiency totals across agents" {
  "$SAGE" create a1 --runtime claude-code >/dev/null 2>&1
  "$SAGE" create a2 --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/a1/tokens.jsonl"
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/a2/tokens.jsonl"
  _add_done_task a1 t1
  _add_done_task a2 t2
  _add_done_task a2 t3
  run "$SAGE" stats --efficiency --json
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq '.total_completed')" == "3" ]]
  [[ "$(echo "$output" | jq '.total_tasks_per_dollar')" != "null" ]]
}
