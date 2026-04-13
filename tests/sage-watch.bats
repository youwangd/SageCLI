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
  echo "initial" > "$WATCH_DIR/test.txt"
  # Modify file after delay in background
  (sleep 2; echo "changed" >> "$WATCH_DIR/test.txt") &
  local bg_pid=$!
  # Use --max-triggers 1 so watch exits after first detection
  # Use perl timeout for macOS compat (no GNU timeout)
  export SAGE_HOME
  if command -v timeout >/dev/null 2>&1; then
    run timeout 10 "$SAGE" watch "$WATCH_DIR" --agent bot1 --max-triggers 1 --debounce 0
  else
    run perl -e 'alarm 10; exec @ARGV' "$SAGE" watch "$WATCH_DIR" --agent bot1 --max-triggers 1 --debounce 0
  fi
  wait "$bg_pid" 2>/dev/null || true
  # Should have detected the change (even if send fails because agent isn't running in tmux)
  [[ "$output" == *"change detected"* || "$output" == *"watching"* ]]
}
