#!/usr/bin/env bats

setup() {
  export SAGE_HOME=$(mktemp -d)
  export AGENTS_DIR="$SAGE_HOME/agents"
  mkdir -p "$AGENTS_DIR"
  SAGE="$BATS_TEST_DIRNAME/../sage"
  WATCH_DIR=$(mktemp -d)
}

teardown() {
  # Collect full process tree (all descendants) BEFORE killing parents
  local all_pids_to_kill=()
  local pid child grandchild
  for pid in "${_ALL_PIDS[@]:-}"; do
    all_pids_to_kill+=("$pid")
    for child in $(pgrep -P "$pid" 2>/dev/null); do
      all_pids_to_kill+=("$child")
      for grandchild in $(pgrep -P "$child" 2>/dev/null); do
        all_pids_to_kill+=("$grandchild")
      done
    done
  done
  # Kill all collected PIDs in one pass (children first, then parents)
  local i
  for (( i=${#all_pids_to_kill[@]}-1; i>=0; i-- )); do
    kill -9 "${all_pids_to_kill[$i]}" 2>/dev/null || true
  done
  for pid in "${_ALL_PIDS[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done
  _ALL_PIDS=()
  rm -rf "$SAGE_HOME" "$WATCH_DIR"
}

_track_pid() { _ALL_PIDS+=("$1"); }

# Trigger a file change after a delay
_trigger_change() {
  local dir="$1" delay="${2:-2}"
  bash -c "sleep $delay; echo changed >> '$dir/test.txt'" &
  _track_pid $!
}

# Run sage watch with a hard timeout — uses a wrapper script to isolate FDs
_run_watch_timeout() {
  local secs="$1"; shift
  local outfile="$SAGE_HOME/_watch_out.txt"
  local wrapper="$SAGE_HOME/_watch_wrapper.sh"
  # Write a wrapper that closes inherited FDs 3+ so bats doesn't wait for them
  cat > "$wrapper" <<'WRAPPER'
exec 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- 2>/dev/null || true
exec "$@"
WRAPPER
  chmod +x "$wrapper"
  bash "$wrapper" "$@" >"$outfile" 2>&1 &
  local wpid=$!
  _track_pid $wpid
  ( sleep "$secs"; kill -9 "$wpid" 2>/dev/null ) &
  local kpid=$!
  _track_pid $kpid
  wait "$wpid" 2>/dev/null || true
  kill -9 "$kpid" 2>/dev/null || true
  wait "$kpid" 2>/dev/null || true
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

@test "watch --plan triggers plan execution on file change" {
  # Create a minimal plan YAML
  local plan_file="$SAGE_HOME/test-plan.yaml"
  cat > "$plan_file" <<'YAML'
goal: test plan
waves:
  - name: wave1
    tasks:
      - agent: tester
        task: run tests
YAML
  _create_agent "tester"
  echo "initial" > "$WATCH_DIR/test.txt"
  local marker="$SAGE_HOME/_plan_ran"
  # Use --on-change to verify --plan is NOT accepted with it
  _trigger_change "$WATCH_DIR"
  _run_watch_timeout 10 "$SAGE" watch "$WATCH_DIR" --plan "$plan_file" --max-triggers 1 --debounce 0
  [[ "$output" == *"change detected"* ]]
  [[ "$output" == *"plan"* ]]
}

@test "watch --plan rejects non-existent plan file" {
  run "$SAGE" watch "$WATCH_DIR" --plan "/nonexistent/plan.yaml"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"not"* || "$output" == *"exist"* || "$output" == *"found"* ]]
}

@test "watch --plan is mutually exclusive with --agent" {
  _create_agent "bot1"
  run "$SAGE" watch "$WATCH_DIR" --agent bot1 --plan "some.yaml"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"mutually exclusive"* || "$output" == *"cannot"* ]]
}

@test "watch --plan is mutually exclusive with --on-change" {
  run "$SAGE" watch "$WATCH_DIR" --on-change "echo hi" --plan "some.yaml"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"mutually exclusive"* || "$output" == *"cannot"* ]]
}

@test "watch --help shows --plan option" {
  run "$SAGE" watch --help
  [[ "$output" == *"--plan"* ]]
}
