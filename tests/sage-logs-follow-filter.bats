#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-ff-$$"
  sage init --quiet 2>/dev/null || true
  sage create worker --runtime bash --quiet 2>/dev/null || true
  mkdir -p "$SAGE_HOME/logs"
  # Use current timestamps so --since 1h always matches
  local now
  now=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s\n' "$now INFO: starting" "$now ERROR: failed" "$now INFO: done" > "$SAGE_HOME/logs/worker.log"
}

teardown() {
  rm -rf "$SAGE_HOME" 2>/dev/null || true
}

@test "logs -f --grep filters live output" {
  # Append a matching line after a delay, verify only it appears
  (sleep 0.3; echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: new failure" >> "$SAGE_HOME/logs/worker.log"; sleep 0.3; echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: recovered" >> "$SAGE_HOME/logs/worker.log") &
  local bgpid=$!
  run timeout 2 sage logs worker -f --grep "ERROR"
  wait "$bgpid" 2>/dev/null || true
  [[ "$output" == *"new failure"* ]]
  [[ "$output" != *"recovered"* ]]
}

@test "logs -f --grep shows existing matches before following" {
  # Verify existing ERROR lines appear when combining -f with --grep
  (sleep 0.3) &
  local bgpid=$!
  run timeout 1 sage logs worker -f --grep "ERROR"
  wait "$bgpid" 2>/dev/null || true
  # Existing match must appear
  [[ "$output" == *"failed"* ]]
  # Non-matching lines must not appear
  [[ "$output" != *"starting"* ]]
}

@test "logs -f --since shows recent lines then follows" {
  # Verify -f + --since shows existing recent lines
  run timeout 2 sage logs worker -f --since 1h
  [[ "$output" == *"starting"* ]]
  [[ "$output" == *"done"* ]]
}

@test "logs -f --grep --since combines all three filters" {
  # Verify -f + --grep + --since all work together
  (sleep 0.3) &
  local bgpid=$!
  run timeout 1 sage logs worker -f --grep "ERROR" --since 1h
  wait "$bgpid" 2>/dev/null || true
  # ERROR line within time window must appear
  [[ "$output" == *"failed"* ]]
  # Non-ERROR lines must not appear
  [[ "$output" != *"starting"* ]]
  [[ "$output" != *"done"* ]]
}
