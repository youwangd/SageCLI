#!/usr/bin/env bats
# tests/sage-alias-count.bats — tests for sage alias ls --count

setup() {
  export SAGE_HOME="$BATS_TEST_TMPDIR/sage-alias-count-$$"
  mkdir -p "$SAGE_HOME"
  printf '{"version":"1.0"}\n' > "$SAGE_HOME/config.json"
}

@test "alias ls --count on empty returns 0" {
  run ./sage alias ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "alias ls --count returns integer count matching registered aliases" {
  ./sage alias set review "send reviewer --headless"
  ./sage alias set audit "send auditor --strict"
  run ./sage alias ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "alias ls --count output is plain integer with no ANSI/whitespace" {
  ./sage alias set a1 "cmd1"
  ./sage alias set a2 "cmd2"
  ./sage alias set a3 "cmd3"
  run ./sage alias ls --count
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
  [[ "$output" != *$'\e['* ]]
  [[ "$output" =~ ^[0-9]+$ ]]
}
