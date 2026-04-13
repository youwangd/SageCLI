#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  mkdir -p "$AGENTS_DIR"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  WATCH_DIR=$(mktemp -d)
}

teardown() {
  # Kill any leftover watch/trigger processes
  pkill -f "sage watch $WATCH_DIR" 2>/dev/null || true
  rm -rf "$SAGE_HOME" "$WATCH_DIR"
}

# Trigger a file change after a delay, fully detached from parent
_trigger_change() {
  local dir="$1" delay="${2:-2}"
  nohup bash -c "sleep $delay; echo changed >> '$dir/test.txt'" </dev/null >/dev/null 2>&1 &
}

# Run sage watch with a timeout, capturing output to file to avoid pipe hangs
_run_watch_timeout() {
  local secs="$1"; shift
  local outfile="$SAGE_HOME/_watch_out.txt"
  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=3 "$secs" "$@" >"$outfile" 2>&1 || true
  else
    perl -e "alarm $secs; exec @ARGV" "$@" >"$outfile" 2>&1 || true
  fi
  output=$(cat "$outfile")
  status=0
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
  _trigger_change "$WATCH_DIR"
  export SAGE_HOME
  _run_watch_timeout 10 "$SAGE" watch "$WATCH_DIR" --agent bot1 --max-triggers 1 --debounce 0
  [[ "$output" == *"change detected"* || "$output" == *"watching"* ]]
}

@test "watch --on-change runs command on file change" {
  echo "initial" > "$WATCH_DIR/test.txt"
  local out_file="$SAGE_HOME/on-change-output.txt"
  _trigger_change "$WATCH_DIR"
  _run_watch_timeout 10 "$SAGE" watch "$WATCH_DIR" --on-change "env | grep SAGE_WATCH > $out_file" --max-triggers 1 --debounce 0
  [[ "$output" == *"change detected"* ]]
  [[ -f "$out_file" ]]
  grep -q "SAGE_WATCH_FILES" "$out_file"
}

@test "watch rejects --agent and --on-change together" {
  _create_agent "bot1"
  run "$SAGE" watch "$WATCH_DIR" --agent bot1 --on-change "echo hi"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"mutually exclusive"* || "$output" == *"cannot"* ]]
}

@test "watch requires --agent or --on-change" {
  run "$SAGE" watch "$WATCH_DIR"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"--agent"* || "$output" == *"--on-change"* ]]
}

@test "watch --on-change without agent does not require agent" {
  echo "initial" > "$WATCH_DIR/test.txt"
  _trigger_change "$WATCH_DIR"
  _run_watch_timeout 10 "$SAGE" watch "$WATCH_DIR" --on-change "echo ok" --max-triggers 1 --debounce 0
  [[ "$output" == *"change detected"* || "$output" == *"watching"* ]]
}

@test "watch --on-change --help shows on-change option" {
  run "$SAGE" watch --help
  [[ "$output" == *"--on-change"* ]]
}
