#!/usr/bin/env bats
# tests/sage-context-count.bats — tests for context ls --count

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-ctx-count-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "context ls --count returns 0 when no keys stored" {
  run "$SAGE" context ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "context ls --count returns exact count of stored keys" {
  "$SAGE" context set key1 "value1" >/dev/null
  "$SAGE" context set key2 "value2" >/dev/null
  "$SAGE" context set key3 "value3" >/dev/null
  run "$SAGE" context ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "context ls --count output is plain integer only" {
  "$SAGE" context set mykey "hello" >/dev/null
  run "$SAGE" context ls --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
