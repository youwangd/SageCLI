#!/usr/bin/env bats
# tests/sage-inbox-count.bats — sage inbox --count emits a plain number for scripting

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-inbox-count-$$"
  mkdir -p "$SAGE_HOME"
  ./sage init --force >/dev/null 2>&1
  local inbox="$SAGE_HOME/agents/.cli/inbox"
  mkdir -p "$inbox"
  local now; now=$(date +%s)
  printf '{"from":"a","ts":%d,"payload":{"status":"done","result":"x"}}\n' "$now"        > "$inbox/m1.json"
  printf '{"from":"b","ts":%d,"payload":{"status":"done","result":"y"}}\n' "$((now+1))" > "$inbox/m2.json"
  printf '{"from":"a","ts":%d,"payload":{"status":"done","result":"z"}}\n' "$((now+2))" > "$inbox/m3.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "inbox --count prints total message count only" {
  run ./sage inbox --count
  [[ "$status" -eq 0 ]]
  [[ "$output" == "3" ]]
}

@test "inbox --count --from a prints filtered count" {
  run ./sage inbox --count --from a
  [[ "$status" -eq 0 ]]
  [[ "$output" == "2" ]]
}

@test "inbox --count on empty inbox prints 0" {
  rm -f "$SAGE_HOME/agents/.cli/inbox"/*.json
  run ./sage inbox --count
  [[ "$status" -eq 0 ]]
  [[ "$output" == "0" ]]
}
