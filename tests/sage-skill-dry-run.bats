#!/usr/bin/env bats
# tests/sage-skill-dry-run.bats — skill rm --dry-run preview (safety affordance)

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,skills}
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

@test "skill rm --dry-run does not delete the skill" {
  mkdir -p "$SAGE_HOME/skills/demo"
  echo '{"name":"demo"}' > "$SAGE_HOME/skills/demo/skill.json"
  echo "hello" > "$SAGE_HOME/skills/demo/prompt.md"
  run sage skill rm demo --dry-run
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/skills/demo" ]
  [ -f "$SAGE_HOME/skills/demo/skill.json" ]
}

@test "skill rm --dry-run reports file count and path" {
  mkdir -p "$SAGE_HOME/skills/demo/sub"
  echo '{"name":"demo"}' > "$SAGE_HOME/skills/demo/skill.json"
  echo "x" > "$SAGE_HOME/skills/demo/prompt.md"
  echo "y" > "$SAGE_HOME/skills/demo/sub/tmpl.txt"
  run sage skill rm demo --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"* ]]
  [[ "$output" == *"3"* ]]
}

@test "skill rm --dry-run fails when skill does not exist" {
  run sage skill rm ghost --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
