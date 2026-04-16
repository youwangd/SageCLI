#!/usr/bin/env bats
# tests/sage-logs-since.bats — logs --since filters by time

setup() {
  export SAGE_HOME="$(mktemp -d)"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1
  mkdir -p "$SAGE_HOME/agents/worker" "$SAGE_HOME/logs"
  echo '{"runtime":"bash","name":"worker"}' > "$SAGE_HOME/agents/worker/runtime.json"
  # Write log lines with timestamps
  local now=$(date +%s)
  local old=$((now - 7200))  # 2 hours ago
  local recent=$((now - 300))  # 5 min ago
  local old_ts=$(date -d "@$old" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$old" '+%Y-%m-%d %H:%M:%S')
  local recent_ts=$(date -d "@$recent" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$recent" '+%Y-%m-%d %H:%M:%S')
  local now_ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "[%s] old line one\n[%s] old line two\n[%s] recent line\n[%s] now line\n" \
    "$old_ts" "$old_ts" "$recent_ts" "$now_ts" > "$SAGE_HOME/logs/worker.log"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "logs --since 30m filters to recent lines only" {
  run sage logs worker --since 30m
  [ "$status" -eq 0 ]
  [[ "$output" == *"recent line"* ]] || [[ "$output" == *"now line"* ]]
  [[ "$output" != *"old line one"* ]]
}

@test "logs --since 1d shows all lines" {
  run sage logs worker --since 1d
  [ "$status" -eq 0 ]
  [[ "$output" == *"old line"* ]]
  [[ "$output" == *"now line"* ]]
}

@test "logs --since combines with --grep" {
  run sage logs worker --since 30m --grep "now"
  [ "$status" -eq 0 ]
  [[ "$output" == *"now line"* ]]
  [[ "$output" != *"old line"* ]]
}

@test "logs --since with invalid duration fails" {
  run sage logs worker --since abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid duration"* ]]
}
