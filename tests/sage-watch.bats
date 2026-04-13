#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  mkdir -p "$AGENTS_DIR"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  WATCH_DIR=$(mktemp -d)
}

teardown() {
  rm -rf "$SAGE_HOME" "$WATCH_DIR"
}

_create_agent() {
  local name="$1"
  mkdir -p "$AGENTS_DIR/$name"
  echo '{"runtime":"bash"}' > "$AGENTS_DIR/$name/runtime.json"
}

@test "watch requires directory argument" {
  run "$SAGE" watch
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"usage"* || "$output" == *"Usage"* || "$output" == *"directory"* ]]
}

@test "watch requires --agent flag" {
  run "$SAGE" watch "$WATCH_DIR"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--agent"* ]]
}

@test "watch rejects nonexistent directory" {
  _create_agent "bot1"
  run "$SAGE" watch /tmp/no-such-dir-$$ --agent bot1
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not"* || "$output" == *"exist"* ]]
}

@test "watch rejects nonexistent agent" {
  run "$SAGE" watch "$WATCH_DIR" --agent no-such-agent
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not found"* || "$output" == *"no agent"* || "$output" == *"No agent"* ]]
}

@test "watch --help shows usage" {
  run "$SAGE" watch --help
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"watch"* ]]
  [[ "$output" == *"--agent"* ]]
  [[ "$output" == *"--pattern"* ]]
}

@test "watch detects file change and exits after trigger" {
  _create_agent "bot1"
  # Create initial file so baseline snapshot exists
  echo "initial" > "$WATCH_DIR/test.txt"
  # Run watch with --max-triggers 1 so it exits after first detection
  # Touch file after a short delay in background
  (sleep 1; echo "changed" > "$WATCH_DIR/test.txt") &
  run timeout 10 "$SAGE" watch "$WATCH_DIR" --agent bot1 --max-triggers 1 --debounce 0
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"change"* || "$output" == *"trigger"* ]]
}
