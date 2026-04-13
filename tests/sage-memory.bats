#!/usr/bin/env bats
# Tests for per-agent persistent memory

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
  sage create worker testbot --runtime bash --quiet 2>/dev/null || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "memory set stores value for agent" {
  sage memory set testbot greeting "hello world"
  [ -f "$SAGE_HOME/agents/testbot/memory/greeting" ]
  [ "$(cat "$SAGE_HOME/agents/testbot/memory/greeting")" = "hello world" ]
}

@test "memory get retrieves stored value" {
  sage memory set testbot mykey myval
  result="$(sage memory get testbot mykey)"
  [ "$result" = "myval" ]
}

@test "memory ls lists all keys" {
  sage memory set testbot k1 v1
  sage memory set testbot k2 v2
  result="$(sage memory ls testbot)"
  echo "$result" | grep -q "k1"
  echo "$result" | grep -q "k2"
}

@test "memory rm deletes a key" {
  sage memory set testbot delme val
  sage memory rm testbot delme
  ! [ -f "$SAGE_HOME/agents/testbot/memory/delme" ]
}

@test "memory clear removes all keys" {
  sage memory set testbot a 1
  sage memory set testbot b 2
  sage memory clear testbot
  result="$(ls "$SAGE_HOME/agents/testbot/memory/" 2>/dev/null | wc -l)"
  [ "$result" -eq 0 ]
}
