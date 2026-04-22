#!/usr/bin/env bats
# tests/sage-config-count.bats — tests for config ls --count

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-cfg-count-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "config ls --count returns 0 when no keys set" {
  run "$SAGE" config ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "config ls --count returns exact count of set keys" {
  "$SAGE" config set key1 "value1" >/dev/null
  "$SAGE" config set key2 "value2" >/dev/null
  "$SAGE" config set key3 "value3" >/dev/null
  run "$SAGE" config ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "config ls --count output is plain integer only" {
  "$SAGE" config set mykey "hello" >/dev/null
  run "$SAGE" config ls --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
