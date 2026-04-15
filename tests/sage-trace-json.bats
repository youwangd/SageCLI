#!/usr/bin/env bats
# tests/sage-trace-json.bats — tests for trace --json output

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-trace-json-$$"
  mkdir -p "$SAGE_HOME"
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init --quiet 2>/dev/null || true
  # Seed trace data
  cat > "$SAGE_HOME/trace.jsonl" <<'EOF'
{"ts":1000,"type":"send","from":"cli","to":"reviewer","task_id":"t1","text":"review code"}
{"ts":1001,"type":"start","agent":"reviewer","task_id":"t1","from":"cli"}
{"ts":1005,"type":"done","agent":"reviewer","task_id":"t1","elapsed":4,"status":"done"}
{"ts":1010,"type":"send","from":"cli","to":"coder","task_id":"t2","text":"write tests"}
{"ts":1011,"type":"start","agent":"coder","task_id":"t2","from":"cli"}
{"ts":1020,"type":"done","agent":"coder","task_id":"t2","elapsed":9,"status":"done"}
EOF
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "trace --json outputs valid JSON array" {
  run sage trace --json
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "trace --json contains all events" {
  run sage trace --json
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 6 ]
}

@test "trace --json with agent filter only includes matching events" {
  run sage trace reviewer --json
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -ge 1 ]
  # All events should reference reviewer
  echo "$output" | jq -e '.[] | select(.agent == "reviewer" or .from == "reviewer" or .to == "reviewer")' >/dev/null
}

@test "trace --json with -n limits output" {
  run sage trace --json -n 2
  [ "$status" -eq 0 ]
  local count
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}
