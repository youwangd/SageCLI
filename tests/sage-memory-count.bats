#!/usr/bin/env bats
# Tests for `sage memory ls <agent> --count`

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-memcount-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create memtestbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "memory ls --count on empty agent returns 0" {
  run "$SAGE" memory ls memtestbot --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "memory ls --count returns integer matching number of keys" {
  "$SAGE" memory set memtestbot k1 v1 >/dev/null 2>&1
  "$SAGE" memory set memtestbot k2 v2 >/dev/null 2>&1
  "$SAGE" memory set memtestbot k3 v3 >/dev/null 2>&1
  run "$SAGE" memory ls memtestbot --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "memory ls --count output is plain integer (scriptable)" {
  "$SAGE" memory set memtestbot onlykey onlyval >/dev/null 2>&1
  run "$SAGE" memory ls memtestbot --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}
