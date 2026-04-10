#!/usr/bin/env bats

setup() {
  export SAGE_HOME="$BATS_TMPDIR/sage-info-$$"
  export SAGE="$BATS_TEST_DIRNAME/../sage"
  rm -rf "$SAGE_HOME"
  "$SAGE" init 2>/dev/null
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "info requires agent name" {
  run "$SAGE" info
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "info fails for nonexistent agent" {
  run "$SAGE" info ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "info shows runtime and model" {
  "$SAGE" create tester --runtime bash 2>/dev/null
  run "$SAGE" info tester
  [ "$status" -eq 0 ]
  [[ "$output" == *"Runtime"* ]]
  [[ "$output" == *"bash"* ]]
}

@test "info shows MCP servers when configured" {
  "$SAGE" create mcpbot --runtime bash 2>/dev/null
  echo '["github","filesystem"]' > "$SAGE_HOME/agents/mcpbot/mcp.json"
  run "$SAGE" info mcpbot
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP"* ]]
  [[ "$output" == *"github"* ]]
}

@test "info shows skills when configured" {
  "$SAGE" create skillbot --runtime bash 2>/dev/null
  echo '["code-review"]' > "$SAGE_HOME/agents/skillbot/skills.json"
  run "$SAGE" info skillbot
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skill"* ]]
  [[ "$output" == *"code-review"* ]]
}

@test "info shows recent tasks" {
  "$SAGE" create worker --runtime bash 2>/dev/null
  mkdir -p "$SAGE_HOME/agents/worker/results"
  echo '{"id":"t1","status":"done","from":"user","queued_at":"2026-04-10T10:00:00Z","finished_at":"2026-04-10T10:01:00Z"}' > "$SAGE_HOME/agents/worker/results/t1.status.json"
  run "$SAGE" info worker
  [ "$status" -eq 0 ]
  [[ "$output" == *"Task"* ]]
  [[ "$output" == *"done"* ]]
}

@test "info --json outputs valid JSON" {
  "$SAGE" create jsonbot --runtime bash 2>/dev/null
  run "$SAGE" info jsonbot --json
  [ "$status" -eq 0 ]
  echo "$output" | jq . >/dev/null 2>&1
}

@test "info shows stopped status when agent not running" {
  "$SAGE" create idle --runtime bash 2>/dev/null
  run "$SAGE" info idle
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped"* ]] || [[ "$output" == *"Stopped"* ]]
}
