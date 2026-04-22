#!/usr/bin/env bats
# Tests for sage memory rm <agent> <key> --dry-run preview safety

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-mem-rm-dry-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create testbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "memory rm --dry-run does NOT delete key" {
  "$SAGE" memory set testbot apikey secret123
  "$SAGE" memory rm testbot apikey --dry-run
  [ -f "$SAGE_HOME/agents/testbot/memory/apikey" ]
}

@test "memory rm --dry-run previews key name and value" {
  "$SAGE" memory set testbot greeting hello
  run "$SAGE" memory rm testbot greeting --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"greeting"* ]]
  [[ "$output" == *"hello"* ]]
}

@test "memory rm --dry-run errors on missing key before dry-run check" {
  run "$SAGE" memory rm testbot nonexistent --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
