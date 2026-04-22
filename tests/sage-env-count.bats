#!/usr/bin/env bats
# tests/sage-env-count.bats — tests for sage env ls <agent> --count
# Extends the --count scripted-polling family to the env subsystem.

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME/agents/worker"
  printf '{"version":"1.0"}\n' > "$SAGE_HOME/config.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "env ls --count on empty env returns 0" {
  run ./sage env ls worker --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "env ls --count returns integer count matching env vars" {
  printf 'API_KEY=secret\nDB_URL=postgres://x\n' > "$SAGE_HOME/agents/worker/env"
  run ./sage env ls worker --count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "env ls --count output is plain integer with no ANSI/whitespace" {
  printf 'A=1\nB=2\nC=3\n' > "$SAGE_HOME/agents/worker/env"
  run ./sage env ls worker --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
  [[ "$output" != *$'\e['* ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}
