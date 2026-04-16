#!/usr/bin/env bats
# tests/sage-history-status.bats — history --status filters by task status

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-hist-status-$$"
  mkdir -p "$SAGE_HOME/agents/alpha/results"
  echo '{"runtime":"bash"}' > "$SAGE_HOME/agents/alpha/runtime.json"
  echo '{}' > "$SAGE_HOME/config.json"

  local now
  now=$(date +%s)

  # 2 done tasks, 1 failed task
  printf '{"id":"t1","status":"done","queued_at":%d,"started_at":%d,"finished_at":%d,"task_text":"build app"}\n' "$((now - 300))" "$((now - 300))" "$((now - 290))" > "$SAGE_HOME/agents/alpha/results/t1.status.json"
  printf '{"id":"t2","status":"failed","queued_at":%d,"started_at":%d,"finished_at":%d,"task_text":"deploy prod"}\n' "$((now - 200))" "$((now - 200))" "$((now - 195))" > "$SAGE_HOME/agents/alpha/results/t2.status.json"
  printf '{"id":"t3","status":"done","queued_at":%d,"started_at":%d,"finished_at":%d,"task_text":"run tests"}\n' "$((now - 100))" "$((now - 100))" "$((now - 95))" > "$SAGE_HOME/agents/alpha/results/t3.status.json"
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "history --status failed shows only failed tasks" {
  run ./sage history --status failed
  [[ "$output" =~ "t2" ]]
  ! [[ "$output" =~ "t1" ]]
  ! [[ "$output" =~ "t3" ]]
}

@test "history --status done shows only done tasks" {
  run ./sage history --status done
  [[ "$output" =~ "t1" ]]
  [[ "$output" =~ "t3" ]]
  ! [[ "$output" =~ "t2" ]]
}

@test "history --status failed --json returns filtered JSON" {
  run ./sage history --status failed --json
  local count
  count=$(echo "$output" | jq 'length')
  [[ "$count" -eq 1 ]]
  echo "$output" | jq -e '.[0].id == "t2"'
}

@test "history --status rejects invalid values" {
  run ./sage history --status bogus
  [[ "$status" -ne 0 ]]
  [[ "$output" =~ "invalid" ]]
}
