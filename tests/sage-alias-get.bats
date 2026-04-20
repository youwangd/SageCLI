#!/usr/bin/env bats
# tests/sage-alias-get.bats — tests for sage alias get <name>

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-alias-get-$$"
  mkdir -p "$SAGE_HOME"
  printf '{"version":"1.0"}\n' > "$SAGE_HOME/config.json"
}

@test "alias get prints expansion (plain, no decoration) for scripting" {
  ./sage alias set review "send reviewer --headless --strict"
  run ./sage alias get review
  [ "$status" -eq 0 ]
  [ "$output" = "send reviewer --headless --strict" ]
}

@test "alias get errors on missing alias with non-zero exit" {
  run ./sage alias get nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "alias get requires name argument" {
  run ./sage alias get
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}
