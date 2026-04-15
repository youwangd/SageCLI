#!/usr/bin/env bats
# tests/sage-help-command.bats — tests for per-command help (sage help <command>)

setup() {
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  export SAGE_HOME="$(mktemp -d)"
  sage init --force >/dev/null 2>&1
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "help send shows send-specific flags" {
  run sage help send
  [ "$status" -eq 0 ]
  [[ "$output" == *"--headless"* ]]
  [[ "$output" == *"--on-fail"* ]]
}

@test "help create shows create-specific flags" {
  run sage help create
  [ "$status" -eq 0 ]
  [[ "$output" == *"--runtime"* ]]
  [[ "$output" == *"--worktree"* ]]
}

@test "help plan shows plan examples" {
  run sage help plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXAMPLES"* ]]
  [[ "$output" == *"--pattern"* ]]
}

@test "help unknown falls back to full help" {
  run sage help nonexistent
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage <command>"* ]]
}

@test "help with no args shows full help" {
  run sage help
  [ "$status" -eq 0 ]
  [[ "$output" == *"sage <command>"* ]]
}

@test "help mcp shows per-command help" {
  run sage help mcp
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUBCOMMANDS"* ]]
  [[ "$output" == *"mcp add"* ]]
  [[ "$output" == *"mcp tools"* ]]
}

@test "help skill shows per-command help" {
  run sage help skill
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUBCOMMANDS"* ]]
  [[ "$output" == *"skill install"* ]]
  [[ "$output" == *"skill run"* ]]
}

@test "help msg shows per-command help" {
  run sage help msg
  [ "$status" -eq 0 ]
  [[ "$output" == *"SUBCOMMANDS"* ]]
  [[ "$output" == *"msg send"* ]]
  [[ "$output" == *"msg ls"* ]]
}
