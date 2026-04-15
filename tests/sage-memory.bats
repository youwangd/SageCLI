#!/usr/bin/env bats
# Tests for per-agent persistent memory

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-memory-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
  "$SAGE" create testbot >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "memory set stores value for agent" {
  "$SAGE" memory set testbot greeting "hello world"
  [ -f "$SAGE_HOME/agents/testbot/memory/greeting" ]
  [ "$(cat "$SAGE_HOME/agents/testbot/memory/greeting")" = "hello world" ]
}

@test "memory get retrieves stored value" {
  "$SAGE" memory set testbot mykey myval
  result="$("$SAGE" memory get testbot mykey)"
  [ "$result" = "myval" ]
}

@test "memory ls lists all keys" {
  "$SAGE" memory set testbot k1 v1
  "$SAGE" memory set testbot k2 v2
  result="$("$SAGE" memory ls testbot)"
  echo "$result" | grep -q "k1"
  echo "$result" | grep -q "k2"
}

@test "memory rm deletes a key" {
  "$SAGE" memory set testbot delme val
  "$SAGE" memory rm testbot delme
  ! [ -f "$SAGE_HOME/agents/testbot/memory/delme" ]
}

@test "memory clear removes all keys" {
  "$SAGE" memory set testbot a 1
  "$SAGE" memory set testbot b 2
  "$SAGE" memory clear testbot
  result="$(ls "$SAGE_HOME/agents/testbot/memory/" 2>/dev/null | wc -l)"
  [ "$result" -eq 0 ]
}

@test "memory ls --json outputs valid JSON" {
  "$SAGE" memory set testbot greeting hello
  "$SAGE" memory set testbot lang bash
  run "$SAGE" memory ls testbot --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.greeting' >/dev/null
  echo "$output" | jq -e '.lang' >/dev/null
}

@test "memory ls --json with empty memory outputs {}" {
  run "$SAGE" memory ls testbot --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'keys | length')" -eq 0 ]
}

@test "help memory shows per-command help" {
  run "$SAGE" help memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory set"* ]]
  [[ "$output" == *"memory ls"* ]]
  [[ "$output" == *"--json"* ]]
}
