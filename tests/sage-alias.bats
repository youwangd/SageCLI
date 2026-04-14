#!/usr/bin/env bats
# tests/sage-alias.bats — tests for sage alias set/ls/rm

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-alias-$$"
  mkdir -p "$SAGE_HOME"
  printf '{"version":"1.0"}\n' > "$SAGE_HOME/config.json"
}

@test "alias set creates alias" {
  run ./sage alias set review "send reviewer --headless --strict"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review"* ]]
}

@test "alias ls lists aliases" {
  ./sage alias set review "send reviewer --headless"
  run ./sage alias ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"review"* ]]
  [[ "$output" == *"send reviewer --headless"* ]]
}

@test "alias rm removes alias" {
  ./sage alias set review "send reviewer --headless"
  run ./sage alias rm review
  [ "$status" -eq 0 ]
  run ./sage alias ls
  [[ "$output" != *"review"* ]]
}

@test "alias rm nonexistent fails" {
  run ./sage alias rm nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "alias set overwrites existing" {
  ./sage alias set review "send reviewer --headless"
  ./sage alias set review "send auditor --strict"
  run ./sage alias ls
  [[ "$output" == *"auditor"* ]]
  [[ "$output" != *"reviewer"* ]]
}
