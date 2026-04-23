#!/usr/bin/env bats
# tests/sage-trace-count.bats — tests for trace --count

SAGE="$BATS_TEST_DIRNAME/../sage"

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-trace-count-$$"
  rm -rf "$SAGE_HOME"
  "$SAGE" init >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "trace --count returns 0 when no trace file" {
  run "$SAGE" trace --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "trace --count returns exact count of events" {
  local tf="$SAGE_HOME/trace.jsonl"
  local now; now=$(date +%s)
  printf '{"ts":%d,"type":"send","from":"cli","to":"a","task_id":"t1","text":"x"}\n' "$now" >> "$tf"
  printf '{"ts":%d,"type":"done","agent":"a","task_id":"t1","elapsed":1}\n' "$now" >> "$tf"
  printf '{"ts":%d,"type":"send","from":"cli","to":"b","task_id":"t2","text":"y"}\n' "$now" >> "$tf"
  run "$SAGE" trace --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "trace --count output is plain integer only" {
  local tf="$SAGE_HOME/trace.jsonl"
  local now; now=$(date +%s)
  printf '{"ts":%d,"type":"send","from":"cli","to":"a","task_id":"t1","text":"x"}\n' "$now" >> "$tf"
  run "$SAGE" trace --count
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "trace --count composes with agent filter" {
  local tf="$SAGE_HOME/trace.jsonl"
  local now; now=$(date +%s)
  printf '{"ts":%d,"type":"send","from":"cli","to":"alpha","task_id":"t1","text":"x"}\n' "$now" >> "$tf"
  printf '{"ts":%d,"type":"send","from":"cli","to":"beta","task_id":"t2","text":"y"}\n' "$now" >> "$tf"
  printf '{"ts":%d,"type":"send","from":"cli","to":"alpha","task_id":"t3","text":"z"}\n' "$now" >> "$tf"
  run "$SAGE" trace alpha --count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}
