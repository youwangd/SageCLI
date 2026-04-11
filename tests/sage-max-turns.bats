#!/usr/bin/env bats
# Tests for agent max-turns feature

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-maxturns-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "create --max-turns 10 stores max_turns in runtime.json" {
  run "$SAGE" create mtbot --max-turns 10
  [ "$status" -eq 0 ]
  local mt
  mt=$(jq -r '.max_turns' "$SAGE_HOME/agents/mtbot/runtime.json")
  [ "$mt" = "10" ]
}

@test "create --max-turns 0 fails" {
  run "$SAGE" create mtbot2 --max-turns 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]] || [[ "$output" == *"must be"* ]]
}

@test "create --max-turns negative fails" {
  run "$SAGE" create mtbot3 --max-turns -5
  [ "$status" -ne 0 ]
}

@test "create --max-turns non-numeric fails" {
  run "$SAGE" create mtbot4 --max-turns abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid"* ]]
}

@test "create without --max-turns has no max_turns" {
  run "$SAGE" create mtbot5
  [ "$status" -eq 0 ]
  local mt
  mt=$(jq -r '.max_turns // "null"' "$SAGE_HOME/agents/mtbot5/runtime.json")
  [ "$mt" = "null" ]
}

@test "info shows max-turns when set" {
  "$SAGE" create mtbot6 --max-turns 25
  run "$SAGE" info mtbot6
  [ "$status" -eq 0 ]
  [[ "$output" == *"25"* ]] || [[ "$output" == *"urns"* ]]
}

@test "info --json includes max_turns" {
  "$SAGE" create mtbot7 --max-turns 50
  run "$SAGE" info mtbot7 --json
  [ "$status" -eq 0 ]
  local mt
  mt=$(echo "$output" | jq -r '.max_turns // "null"')
  [ "$mt" = "50" ]
}

@test "create --max-turns and --timeout can be combined" {
  run "$SAGE" create mtbot8 --max-turns 20 --timeout 30m
  [ "$status" -eq 0 ]
  local mt ts
  mt=$(jq -r '.max_turns' "$SAGE_HOME/agents/mtbot8/runtime.json")
  ts=$(jq -r '.timeout_seconds' "$SAGE_HOME/agents/mtbot8/runtime.json")
  [ "$mt" = "20" ]
  [ "$ts" = "1800" ]
}
