#!/usr/bin/env bats
# tests/sage-tasks-count.bats — sage tasks --count prints plain integer

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$(mktemp -d)"
  sage init --force >/dev/null 2>&1
  sage create tester --runtime bash >/dev/null 2>&1
  local rd="$SAGE_HOME/agents/tester/results"
  mkdir -p "$rd"
  local now=$(date +%s)
  echo "{\"id\":\"task-001\",\"status\":\"done\",\"from\":\"cli\",\"queued_at\":$((now-120)),\"finished_at\":$((now-10)),\"task_text\":\"fix bug\"}" > "$rd/task-001.status.json"
  echo "{\"id\":\"task-002\",\"status\":\"failed\",\"from\":\"cli\",\"queued_at\":$((now-60)),\"finished_at\":$((now-5)),\"task_text\":\"deploy\"}" > "$rd/task-002.status.json"
  echo "{\"id\":\"task-003\",\"status\":\"running\",\"from\":\"api\",\"queued_at\":$((now-30)),\"task_text\":\"test suite\"}" > "$rd/task-003.status.json"
}

teardown() { rm -rf "$SAGE_HOME"; }

@test "tasks --count prints plain integer of all tasks" {
  run sage tasks --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "tasks --count composes with --status filter" {
  run sage tasks --status failed --count
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "tasks --count output is scriptable (pure digits)" {
  local n
  n=$(sage tasks --status running --count)
  [[ "$n" =~ ^[0-9]+$ ]]
  [ "$n" -eq 1 ]
}
