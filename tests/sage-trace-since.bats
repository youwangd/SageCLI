#!/usr/bin/env bats
# tests/sage-trace-since.bats — trace --since filters events by time window

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-trace-since-$$"
  mkdir -p "$SAGE_HOME/agents/alpha"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"

  local now old
  now=$(date +%s)
  old=$((now - 7200))  # 2 hours ago

  # Write trace events: 2 old, 2 recent
  printf '{"ts":%d,"type":"send","from":"cli","to":"alpha","task_id":"t1","text":"old task 1"}\n' "$old" > "$SAGE_HOME/trace.jsonl"
  printf '{"ts":%d,"type":"done","agent":"alpha","task_id":"t1","elapsed":5,"status":"done"}\n' "$((old + 5))" >> "$SAGE_HOME/trace.jsonl"
  printf '{"ts":%d,"type":"send","from":"cli","to":"alpha","task_id":"t2","text":"recent task"}\n' "$((now - 60))" >> "$SAGE_HOME/trace.jsonl"
  printf '{"ts":%d,"type":"done","agent":"alpha","task_id":"t2","elapsed":3,"status":"done"}\n' "$((now - 57))" >> "$SAGE_HOME/trace.jsonl"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "trace --since 1h shows only recent events" {
  run ./sage trace --since 1h
  [[ "$output" =~ "t2" ]]
  ! [[ "$output" =~ "t1" ]]
}

@test "trace --since 1d shows all events" {
  run ./sage trace --since 1d
  [[ "$output" =~ "t1" ]]
  [[ "$output" =~ "t2" ]]
}

@test "trace --since 30m excludes 1h-old events" {
  run ./sage trace --since 30m
  [[ "$output" =~ "t2" ]]
  ! [[ "$output" =~ "t1" ]]
}

@test "trace --since works with --json" {
  run ./sage trace --since 1h --json
  local count
  count=$(echo "$output" | jq 'length')
  [[ "$count" -eq 2 ]]
  echo "$output" | jq -e '.[0].task_id == "t2"'
}
