#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --force >/dev/null 2>&1
  # Create two agents with log files
  mkdir -p "$SAGE_HOME/agents/alpha" "$SAGE_HOME/agents/beta" "$SAGE_HOME/logs"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/beta/runtime.json"
  echo "alpha line 1" > "$SAGE_HOME/logs/alpha.log"
  echo "beta line 1" > "$SAGE_HOME/logs/beta.log"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "logs --all shows output from multiple agents" {
  run sage logs --all
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "logs --all prefixes lines with agent name" {
  run sage logs --all
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"[alpha]"* ]]
  [[ "$output" == *"[beta]"* ]]
}

@test "logs --all skips agents without log files" {
  mkdir -p "$SAGE_HOME/agents/gamma"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/gamma/runtime.json"
  # gamma has no log file
  run sage logs --all
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"[alpha]"* ]]
  [[ "$output" != *"[gamma]"* ]]
}

@test "logs --all shows message when no logs exist" {
  rm -f "$SAGE_HOME/logs/"*.log
  run sage logs --all
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"no agent logs"* ]]
}

@test "logs --all includes log content" {
  run sage logs --all
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"alpha line 1"* ]]
  [[ "$output" == *"beta line 1"* ]]
}
