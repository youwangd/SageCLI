#!/usr/bin/env bats
# tests/sage-inbox-from.bats — sage inbox --from <agent> filters messages by sender

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-inbox-from-$$"
  mkdir -p "$SAGE_HOME"
  ./sage init --force >/dev/null 2>&1
  local inbox="$SAGE_HOME/agents/.cli/inbox"
  mkdir -p "$inbox"
  local now; now=$(date +%s)
  printf '{"from":"worker-1","ts":%d,"payload":{"status":"done","result":"ok1"}}\n' "$now"        > "$inbox/m1.json"
  printf '{"from":"worker-2","ts":%d,"payload":{"status":"done","result":"ok2"}}\n' "$((now+1))" > "$inbox/m2.json"
  printf '{"from":"worker-1","ts":%d,"payload":{"status":"failed","result":"err"}}\n' "$((now+2))" > "$inbox/m3.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "inbox --from worker-1 returns only worker-1 messages" {
  run ./sage inbox --from worker-1 --json
  [[ "$status" -eq 0 ]]
  local n; n=$(echo "$output" | jq -s 'length')
  [[ "$n" -eq 2 ]]
  echo "$output" | jq -s '.[].from' | grep -qv worker-2
}

@test "inbox --from worker-2 returns one message" {
  run ./sage inbox --from worker-2 --json
  [[ "$status" -eq 0 ]]
  local n; n=$(echo "$output" | jq -s 'length')
  [[ "$n" -eq 1 ]]
}

@test "inbox --from nobody returns zero messages" {
  run ./sage inbox --from nobody --json
  [[ "$status" -eq 0 ]]
  [[ -z "${output// }" ]] || { local n; n=$(echo "$output" | jq -s 'length'); [[ "$n" -eq 0 ]]; }
}
