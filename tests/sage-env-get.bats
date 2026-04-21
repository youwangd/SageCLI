#!/usr/bin/env bats
# Tests for `sage env get <agent> <KEY>` — plain-value retrieval for scripted use

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-env-get-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create envbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "env get prints plain value for existing key" {
  "$SAGE" env set envbot API_KEY=secret-value-123 >/dev/null
  run "$SAGE" env get envbot API_KEY
  [ "$status" -eq 0 ]
  [ "$output" = "secret-value-123" ]
}

@test "env get errors on missing key" {
  run "$SAGE" env get envbot NO_SUCH_KEY
  [ "$status" -ne 0 ]
}

@test "env get errors on missing args" {
  run "$SAGE" env get
  [ "$status" -ne 0 ]
  run "$SAGE" env get envbot
  [ "$status" -ne 0 ]
}
