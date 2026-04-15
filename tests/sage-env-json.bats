#!/usr/bin/env bats
# tests/sage-env-json.bats — env ls --json + help context/env

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-env-json-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create testbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "env ls --json outputs valid JSON" {
  "$SAGE" env set testbot API=hello >/dev/null
  "$SAGE" env set testbot MODEL=gpt4 >/dev/null
  run "$SAGE" env ls testbot --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.API' >/dev/null
  echo "$output" | jq -e '.MODEL' >/dev/null
}

@test "env ls --json with empty env outputs {}" {
  run "$SAGE" env ls testbot --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'keys | length')" -eq 0 ]
}

@test "env ls --json masks values" {
  "$SAGE" env set testbot SECRET=supersecretvalue >/dev/null
  run "$SAGE" env ls testbot --json
  [ "$status" -eq 0 ]
  local val
  val=$(echo "$output" | jq -r '.SECRET')
  [[ "$val" != "supersecretvalue" ]]
  [[ "$val" == *"***"* ]]
}

@test "help context shows per-command help" {
  run "$SAGE" help context
  [ "$status" -eq 0 ]
  [[ "$output" == *"context set"* ]]
  [[ "$output" == *"context ls"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"--file"* ]]
}

@test "help env shows per-command help" {
  run "$SAGE" help env
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUBCOMMANDS"* ]]
  [[ "$output" == *"env set"* ]]
  [[ "$output" == *"env ls"* ]]
  [[ "$output" == *"--json"* ]]
  [[ "$output" == *"scope"* ]]
}
