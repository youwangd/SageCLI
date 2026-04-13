#!/usr/bin/env bats
# Tests for agent concurrency limit (max-agents config)

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-maxagents-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  # Kill any test agents
  for pidfile in "$SAGE_HOME"/agents/*/.pid; do
    [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null || true
  done
  sleep 0.2
  rm -rf "$SAGE_HOME"
}

@test "max-agents: no limit by default allows start" {
  "$SAGE" create bot1 >/dev/null 2>&1
  # Should succeed — no limit set
  run "$SAGE" start bot1
  # start may fail due to no runtime, but should NOT fail with "concurrency limit"
  [[ "$output" != *"concurrency limit"* ]]
}

@test "max-agents: config set max-agents stores value" {
  "$SAGE" config set max-agents 2
  result="$("$SAGE" config get max-agents)"
  [ "$result" = "2" ]
}

@test "max-agents: start refuses when limit reached" {
  "$SAGE" config set max-agents 1
  "$SAGE" create bot1 >/dev/null 2>&1
  "$SAGE" create bot2 >/dev/null 2>&1
  # Simulate bot1 running by creating a pid file with a live process
  bash -c "sleep 60" &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/bot1/.pid"
  # Now try to start bot2 — should fail
  run "$SAGE" start bot2
  kill "$pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"concurrency limit"* ]]
}

@test "max-agents: send refuses when limit reached in non-headless" {
  "$SAGE" config set max-agents 1
  "$SAGE" create bot1 >/dev/null 2>&1
  "$SAGE" create bot2 >/dev/null 2>&1
  bash -c "sleep 60" &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/bot1/.pid"
  run "$SAGE" send bot2 "hello"
  kill "$pid" 2>/dev/null || true
  [ "$status" -ne 0 ]
  [[ "$output" == *"concurrency limit"* ]]
}

@test "max-agents: start allowed when under limit" {
  "$SAGE" config set max-agents 2
  "$SAGE" create bot1 >/dev/null 2>&1
  "$SAGE" create bot2 >/dev/null 2>&1
  bash -c "sleep 60" &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/bot1/.pid"
  # bot2 start should NOT fail with concurrency limit (1 running, limit 2)
  run "$SAGE" start bot2
  kill "$pid" 2>/dev/null || true
  [[ "$output" != *"concurrency limit"* ]]
}
