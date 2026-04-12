#!/usr/bin/env bats
# Tests for sage stats --tokens — per-agent token usage tracking

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-tokens-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "stats --tokens with no agents shows header" {
  run "$SAGE" stats --tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tokens"* ]]
}

@test "stats --tokens shows per-agent token counts" {
  "$SAGE" create alpha >/dev/null 2>&1
  echo '{"ts":1000,"input":500,"output":200}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  echo '{"ts":2000,"input":300,"output":100}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  run "$SAGE" stats --tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"800"* ]]
  [[ "$output" == *"300"* ]]
}

@test "stats --tokens shows totals across agents" {
  "$SAGE" create alpha >/dev/null 2>&1
  "$SAGE" create beta >/dev/null 2>&1
  echo '{"ts":1000,"input":500,"output":200}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  echo '{"ts":1000,"input":1000,"output":400}' >> "$SAGE_HOME/agents/beta/tokens.jsonl"
  run "$SAGE" stats --tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"1500"* ]]
  [[ "$output" == *"600"* ]]
}

@test "stats --tokens --json outputs valid JSON with token data" {
  "$SAGE" create worker >/dev/null 2>&1
  echo '{"ts":1000,"input":500,"output":200}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  run "$SAGE" stats --tokens --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
  [[ "$(echo "$output" | jq -r '.agents[0].name')" == "worker" ]]
  [[ "$(echo "$output" | jq -r '.agents[0].input_tokens')" == "500" ]]
  [[ "$(echo "$output" | jq -r '.agents[0].output_tokens')" == "200" ]]
  [[ "$(echo "$output" | jq -r '.total_input')" == "500" ]]
}

@test "stats --tokens ignores agents with no token data" {
  "$SAGE" create alpha >/dev/null 2>&1
  "$SAGE" create beta >/dev/null 2>&1
  echo '{"ts":1000,"input":500,"output":200}' >> "$SAGE_HOME/agents/alpha/tokens.jsonl"
  run "$SAGE" stats --tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  # beta should not appear since it has no tokens
  [[ "$output" != *"beta"* ]] || [[ "$output" == *"beta"*"0"* ]]
}

@test "stats --tokens handles malformed token lines gracefully" {
  "$SAGE" create worker >/dev/null 2>&1
  echo 'not json' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  echo '{"ts":1000,"input":500,"output":200}' >> "$SAGE_HOME/agents/worker/tokens.jsonl"
  run "$SAGE" stats --tokens
  [ "$status" -eq 0 ]
  [[ "$output" == *"500"* ]]
}
