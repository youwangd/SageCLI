#!/usr/bin/env bats
# Tests for agent timeout feature

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-timeout-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "create --timeout 30m stores timeout_seconds in runtime.json" {
  run "$SAGE" create tbot --timeout 30m
  [ "$status" -eq 0 ]
  local ts
  ts=$(jq -r '.timeout_seconds' "$SAGE_HOME/agents/tbot/runtime.json")
  [ "$ts" = "1800" ]
}

@test "create --timeout 2h stores 7200 seconds" {
  run "$SAGE" create tbot2 --timeout 2h
  [ "$status" -eq 0 ]
  local ts
  ts=$(jq -r '.timeout_seconds' "$SAGE_HOME/agents/tbot2/runtime.json")
  [ "$ts" = "7200" ]
}

@test "create --timeout 90s stores 90 seconds" {
  run "$SAGE" create tbot3 --timeout 90s
  [ "$status" -eq 0 ]
  local ts
  ts=$(jq -r '.timeout_seconds' "$SAGE_HOME/agents/tbot3/runtime.json")
  [ "$ts" = "90" ]
}

@test "create --timeout 45 (bare number) stores 45 seconds" {
  run "$SAGE" create tbot4 --timeout 45
  [ "$status" -eq 0 ]
  local ts
  ts=$(jq -r '.timeout_seconds' "$SAGE_HOME/agents/tbot4/runtime.json")
  [ "$ts" = "45" ]
}

@test "create --timeout invalid format fails" {
  run "$SAGE" create tbot5 --timeout abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid timeout"* ]]
}

@test "create without --timeout has no timeout_seconds" {
  run "$SAGE" create tbot6
  [ "$status" -eq 0 ]
  local ts
  ts=$(jq -r '.timeout_seconds // "null"' "$SAGE_HOME/agents/tbot6/runtime.json")
  [ "$ts" = "null" ]
}

@test "info shows timeout when set" {
  "$SAGE" create tbot7 --timeout 30m
  run "$SAGE" info tbot7
  [ "$status" -eq 0 ]
  [[ "$output" == *"30m"* ]] || [[ "$output" == *"1800"* ]] || [[ "$output" == *"imeout"* ]]
}

@test "info --json includes timeout_seconds" {
  "$SAGE" create tbot8 --timeout 1h
  run "$SAGE" info tbot8 --json
  [ "$status" -eq 0 ]
  local ts
  ts=$(echo "$output" | jq -r '.timeout // .timeout_seconds // "null"')
  [[ "$ts" != "null" ]]
}
