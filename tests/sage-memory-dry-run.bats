#!/usr/bin/env bats
# Tests for sage memory clear --dry-run preview safety

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-mem-dry-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create testbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "memory clear --dry-run does NOT delete keys" {
  "$SAGE" memory set testbot a 1
  "$SAGE" memory set testbot b 2
  "$SAGE" memory clear testbot --dry-run
  [ -f "$SAGE_HOME/agents/testbot/memory/a" ]
  [ -f "$SAGE_HOME/agents/testbot/memory/b" ]
}

@test "memory clear --dry-run previews count and key names" {
  "$SAGE" memory set testbot alpha 1
  "$SAGE" memory set testbot beta 2
  run "$SAGE" memory clear testbot --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "memory clear --dry-run on empty memory reports 0" {
  run "$SAGE" memory clear testbot --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"0"* ]]
}
