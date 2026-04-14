#!/usr/bin/env bats
# tests/sage-history-since.bats — tests for history --since time filter

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-since-$$"
  sage init --quiet 2>/dev/null || true
  sage create worker --runtime bash 2>/dev/null || true
}

_make_task() {
  local agent="$1" id="$2" ts="$3"
  local dir="$SAGE_HOME/agents/$agent/results"
  mkdir -p "$dir"
  printf '{"id":"%s","status":"done","queued_at":%s,"started_at":%s,"finished_at":%s}' \
    "$id" "$ts" "$ts" "$((ts+10))" > "$dir/${id}.status.json"
}

@test "history --since 1h shows recent tasks only" {
  local now; now=$(date +%s)
  _make_task worker "recent-$$" "$((now - 1800))"    # 30min ago
  _make_task worker "old-$$" "$((now - 7200))"        # 2h ago
  run sage history --since 1h
  [ "$status" -eq 0 ]
  [[ "$output" == *"recent-"* ]]
  [[ "$output" != *"old-"* ]]
}

@test "history --since 2d shows tasks within 2 days" {
  local now; now=$(date +%s)
  _make_task worker "today-$$" "$((now - 3600))"      # 1h ago
  _make_task worker "ancient-$$" "$((now - 259200))"   # 3d ago
  run sage history --since 2d
  [ "$status" -eq 0 ]
  [[ "$output" == *"today-"* ]]
  [[ "$output" != *"ancient-"* ]]
}

@test "history --since 30m with --json works" {
  local now; now=$(date +%s)
  _make_task worker "fresh-$$" "$((now - 600))"       # 10min ago
  _make_task worker "stale-$$" "$((now - 3600))"      # 1h ago
  run sage history --since 30m --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 1' >/dev/null
  echo "$output" | jq -e '.[0].id | startswith("fresh-")' >/dev/null
}

@test "history --since works with --tag filter" {
  local now; now=$(date +%s)
  local dir="$SAGE_HOME/agents/worker/results"
  mkdir -p "$dir"
  printf '{"id":"tagged-%s","status":"done","queued_at":%s,"tags":["review"]}' "$$" "$((now - 600))" > "$dir/tagged-$$.status.json"
  printf '{"id":"untagged-%s","status":"done","queued_at":%s}' "$$" "$((now - 600))" > "$dir/untagged-$$.status.json"
  run sage history --since 1h --tag review
  [ "$status" -eq 0 ]
  [[ "$output" == *"tagged-"* ]]
  [[ "$output" != *"untagged-"* ]]
}

@test "history --since rejects invalid duration" {
  run sage history --since abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid duration"* ]]
}
