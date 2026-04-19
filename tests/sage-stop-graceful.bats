#!/usr/bin/env bats
# tests/sage-stop-graceful.bats — graceful stop with SIGTERM then SIGKILL

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-stop-graceful-$$"
  mkdir -p "$SAGE_HOME/agents/worker" "$SAGE_HOME/logs"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/worker/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"
}

@test "stop --graceful sends SIGTERM first then cleans up" {
  # Start a process that exits cleanly on SIGTERM (use wait to let trap fire)
  bash -c 'trap "exit 0" TERM; sleep 300 & wait' &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/worker/.pid"
  # Graceful stop with 3s timeout (enough for trap to fire)
  run "$BATS_TEST_DIRNAME/../sage" stop --graceful 3s worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped worker"* ]]
  # Process should be gone
  ! kill -0 "$pid" 2>/dev/null
}

@test "stop --graceful force-kills after timeout" {
  # Start a process that ignores SIGTERM
  bash -c 'trap "" TERM; sleep 300' &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/worker/.pid"
  run "$BATS_TEST_DIRNAME/../sage" stop --graceful 1s worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"force-killed"* ]]
  ! kill -0 "$pid" 2>/dev/null
}

@test "stop --graceful requires duration argument" {
  run "$BATS_TEST_DIRNAME/../sage" stop --graceful
  [ "$status" -ne 0 ]
}

@test "stop --graceful accepts seconds duration" {
  # 0s timeout means immediate SIGKILL after SIGTERM — tests parsing
  bash -c 'trap "exit 0" TERM; sleep 300' &
  local pid=$!
  echo "$pid" > "$SAGE_HOME/agents/worker/.pid"
  run "$BATS_TEST_DIRNAME/../sage" stop --graceful 1s worker
  [ "$status" -eq 0 ]
  ! kill -0 "$pid" 2>/dev/null
}
