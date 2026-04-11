#!/usr/bin/env bats
# Tests for per-agent environment variable management

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-env-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create envbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "env set stores KEY=VALUE in agent env file" {
  run "$SAGE" env set envbot MY_KEY=hello
  [ "$status" -eq 0 ]
  grep -q "MY_KEY=hello" "$SAGE_HOME/agents/envbot/env"
}

@test "env set multiple vars" {
  "$SAGE" env set envbot A=1 >/dev/null
  "$SAGE" env set envbot B=2 >/dev/null
  run "$SAGE" env ls envbot
  [ "$status" -eq 0 ]
  [[ "$output" == *"A="* ]]
  [[ "$output" == *"B="* ]]
}

@test "env ls masks values" {
  "$SAGE" env set envbot SECRET_KEY=supersecret123 >/dev/null
  run "$SAGE" env ls envbot
  [ "$status" -eq 0 ]
  [[ "$output" != *"supersecret123"* ]]
  [[ "$output" == *"SECRET_KEY="* ]]
}

@test "env rm removes a key" {
  "$SAGE" env set envbot REMOVE_ME=yes >/dev/null
  "$SAGE" env rm envbot REMOVE_ME >/dev/null
  run "$SAGE" env ls envbot
  [[ "$output" != *"REMOVE_ME"* ]]
}

@test "env set overwrites existing key" {
  "$SAGE" env set envbot DUP=old >/dev/null
  "$SAGE" env set envbot DUP=new >/dev/null
  local val
  val=$(grep "^DUP=" "$SAGE_HOME/agents/envbot/env" | tail -1)
  [ "$val" = "DUP=new" ]
  # Should only appear once
  local count
  count=$(grep -c "^DUP=" "$SAGE_HOME/agents/envbot/env")
  [ "$count" -eq 1 ]
}

@test "env set rejects invalid format (no =)" {
  run "$SAGE" env set envbot BADFORMAT
  [ "$status" -ne 0 ]
}

@test "create --env sets env vars at creation" {
  run "$SAGE" create envbot2 --env API_KEY=abc123 --env MODEL=gpt4
  [ "$status" -eq 0 ]
  grep -q "API_KEY=abc123" "$SAGE_HOME/agents/envbot2/env"
  grep -q "MODEL=gpt4" "$SAGE_HOME/agents/envbot2/env"
}

@test "env on nonexistent agent fails" {
  run "$SAGE" env set noagent KEY=val
  [ "$status" -ne 0 ]
}

@test "info shows env var count" {
  "$SAGE" env set envbot X=1 >/dev/null
  "$SAGE" env set envbot Y=2 >/dev/null
  run "$SAGE" info envbot
  [ "$status" -eq 0 ]
  [[ "$output" == *"Env Vars:"* ]] || [[ "$output" == *"env"* ]]
}
