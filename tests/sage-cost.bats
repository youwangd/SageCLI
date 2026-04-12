#!/usr/bin/env bats
# Tests for sage stats --cost — per-agent cost estimation

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-cost-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "stats --cost with no agents shows header" {
  run "$SAGE" stats --cost
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cost"* ]]
}

@test "stats --cost calculates cost from tokens and runtime pricing" {
  "$SAGE" create alpha --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  run "$SAGE" stats --cost
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"$"* ]]
}

@test "stats --cost --json outputs valid JSON with cost data" {
  "$SAGE" create worker --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  run "$SAGE" stats --cost --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
  [[ "$(echo "$output" | jq -r '.agents[0].name')" == "worker" ]]
  [[ "$(echo "$output" | jq '.agents[0].cost_usd')" != "null" ]]
  [[ "$(echo "$output" | jq '.total_cost_usd')" != "null" ]]
}

@test "stats --cost uses zero for unknown runtimes" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  echo '{"ts":1000,"input":1000,"output":500}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  run "$SAGE" stats --cost --json
  [ "$status" -eq 0 ]
  [[ "$(echo "$output" | jq '.agents[0].cost_usd')" == "0" ]]
}

@test "stats --cost respects custom pricing config" {
  "$SAGE" create worker --runtime bash >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":1000000}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  "$SAGE" config set pricing.bash.input 5.00 >/dev/null 2>&1
  "$SAGE" config set pricing.bash.output 15.00 >/dev/null 2>&1
  run "$SAGE" stats --cost --json
  [ "$status" -eq 0 ]
  # 1M input * $5/M + 1M output * $15/M = $20
  [[ "$(echo "$output" | jq '.agents[0].cost_usd')" == "20" ]]
}

@test "stats --cost totals across multiple agents" {
  "$SAGE" create a1 --runtime claude-code >/dev/null 2>&1
  "$SAGE" create a2 --runtime claude-code >/dev/null 2>&1
  echo '{"ts":1000,"input":1000000,"output":500000}' >> "$SAGE_HOME/agents/a1/tokens.jsonl"
  echo '{"ts":1000,"input":2000000,"output":1000000}' >> "$SAGE_HOME/agents/a2/tokens.jsonl"
  run "$SAGE" stats --cost --json
  [ "$status" -eq 0 ]
  local a1_cost a2_cost total
  a1_cost=$(echo "$output" | jq '[.agents[] | select(.name=="a1")] | .[0].cost_usd')
  a2_cost=$(echo "$output" | jq '[.agents[] | select(.name=="a2")] | .[0].cost_usd')
  total=$(echo "$output" | jq '.total_cost_usd')
  # total should equal sum of individual costs
  [[ "$(echo "$a1_cost + $a2_cost" | bc)" == "$total" ]]
}
