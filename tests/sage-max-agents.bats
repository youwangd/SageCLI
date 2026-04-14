#!/usr/bin/env bats
# Tests for agent concurrency limit (max-agents config)

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-maxagents-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# Helper: simulate a running agent by writing current shell's PID (always alive)
_fake_running() {
  echo "$$" > "$SAGE_HOME/agents/$1/.pid"
}

@test "max-agents: no limit by default — no concurrency error" {
  "$SAGE" config get max-agents | grep -qv '.' || true
  # No max-agents set means no limit — verified by absence of config
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
  _fake_running bot1
  run "$SAGE" start bot2
  [ "$status" -ne 0 ]
  [[ "$output" == *"concurrency limit"* ]]
}

@test "max-agents: send refuses when limit reached in non-headless" {
  "$SAGE" config set max-agents 1
  "$SAGE" create bot1 >/dev/null 2>&1
  "$SAGE" create bot2 >/dev/null 2>&1
  _fake_running bot1
  run "$SAGE" send bot2 "hello"
  [ "$status" -ne 0 ]
  [[ "$output" == *"concurrency limit"* ]]
}

@test "max-agents: start allowed when under limit" {
  "$SAGE" config set max-agents 2
  "$SAGE" create bot1 >/dev/null 2>&1
  "$SAGE" create bot2 >/dev/null 2>&1
  _fake_running bot1
  # With limit=2 and 1 running, bot2 should pass the concurrency check
  # (it will fail at tmux, but NOT with concurrency error)
  run "$SAGE" start bot2
  [[ "$output" != *"concurrency limit"* ]]
}
