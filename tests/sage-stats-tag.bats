#!/usr/bin/env bats
# tests/sage-stats-tag.bats — sage stats --tag <label> filters to tasks with that tag

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-stats-tag-$$"
  mkdir -p "$SAGE_HOME"
  ./sage init --force >/dev/null 2>&1
  ./sage create worker --runtime bash >/dev/null 2>&1
  local rd="$SAGE_HOME/agents/worker/results"
  mkdir -p "$rd"
  local now; now=$(date +%s)
  # 2 done tasks tagged "nightly"
  printf '{"status":"done","started_at":%d,"finished_at":%d,"tags":["nightly"]}\n' "$now" "$((now + 60))" > "$rd/n1.status.json"
  printf '{"status":"done","started_at":%d,"finished_at":%d,"tags":["nightly","backup"]}\n' "$now" "$((now + 30))" > "$rd/n2.status.json"
  # 1 failed task tagged "ci"
  printf '{"status":"failed","started_at":%d,"finished_at":%d,"tags":["ci"]}\n' "$now" "$((now + 10))" > "$rd/c1.status.json"
  # 1 done task with no tags
  printf '{"status":"done","started_at":%d,"finished_at":%d,"tags":[]}\n' "$now" "$((now + 5))" > "$rd/u1.status.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "stats --tag nightly counts only nightly-tagged tasks" {
  run ./sage stats --tag nightly --json
  [[ "$status" -eq 0 ]]
  local d; d=$(echo "$output" | jq '.tasks_done')
  local f; f=$(echo "$output" | jq '.tasks_failed')
  [[ "$d" -eq 2 ]]
  [[ "$f" -eq 0 ]]
}

@test "stats --tag ci counts only ci-tagged failed task" {
  run ./sage stats --tag ci --json
  [[ "$status" -eq 0 ]]
  local d; d=$(echo "$output" | jq '.tasks_done')
  local f; f=$(echo "$output" | jq '.tasks_failed')
  [[ "$d" -eq 0 ]]
  [[ "$f" -eq 1 ]]
}

@test "stats --tag nonexistent shows zero tasks" {
  run ./sage stats --tag nonexistent --json
  [[ "$status" -eq 0 ]]
  local d; d=$(echo "$output" | jq '.tasks_done')
  local f; f=$(echo "$output" | jq '.tasks_failed')
  [[ "$d" -eq 0 ]]
  [[ "$f" -eq 0 ]]
}
