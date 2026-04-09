#!/usr/bin/env bats
# tests/sage-skill.bats — Skills system tests

setup() {
  export SAGE_HOME=$(mktemp -d)
  mkdir -p "$SAGE_HOME"/{agents,runtimes,skills}
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'EOF'
runtime_start() { :; }
runtime_inject() { echo "ok"; }
EOF
  export PATH="$BATS_TEST_DIRNAME/..:$PATH"
  sage init >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$SAGE_HOME"
}

# ── skill ls ──

@test "skill ls shows no skills when empty" {
  run sage skill ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"no skills"* ]]
}

@test "skill ls lists installed skills" {
  mkdir -p "$SAGE_HOME/skills/code-review"
  cat > "$SAGE_HOME/skills/code-review/skill.json" << 'EOF'
{"name":"code-review","version":"1.0.0","description":"Code review templates"}
EOF
  run sage skill ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"code-review"* ]]
  [[ "$output" == *"Code review templates"* ]]
}

# ── skill install ──

@test "skill install requires argument" {
  run sage skill install
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "skill install from local directory" {
  local src=$(mktemp -d)
  mkdir -p "$src"
  cat > "$src/skill.json" << 'EOF'
{"name":"test-skill","version":"0.1.0","description":"A test skill"}
EOF
  echo "You are a test agent" > "$src/prompt.md"
  run sage skill install "$src"
  [ "$status" -eq 0 ]
  [ -f "$SAGE_HOME/skills/test-skill/skill.json" ]
  [ -f "$SAGE_HOME/skills/test-skill/prompt.md" ]
  rm -rf "$src"
}

@test "skill install rejects directory without skill.json" {
  local src=$(mktemp -d)
  run sage skill install "$src"
  [ "$status" -ne 0 ]
  [[ "$output" == *"skill.json"* ]]
  rm -rf "$src"
}

# ── skill rm ──

@test "skill rm requires argument" {
  run sage skill rm
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "skill rm removes installed skill" {
  mkdir -p "$SAGE_HOME/skills/old-skill"
  cat > "$SAGE_HOME/skills/old-skill/skill.json" << 'EOF'
{"name":"old-skill","version":"1.0.0","description":"Remove me"}
EOF
  run sage skill rm old-skill
  [ "$status" -eq 0 ]
  [ ! -d "$SAGE_HOME/skills/old-skill" ]
}

@test "skill rm fails for nonexistent skill" {
  run sage skill rm ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ── create --skill ──

@test "create with --skill injects skill prompt into agent" {
  mkdir -p "$SAGE_HOME/skills/reviewer"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","version":"1.0.0","description":"Review code","prompts":["prompt.md"]}
EOF
  echo "Review all code carefully" > "$SAGE_HOME/skills/reviewer/prompt.md"
  run sage create worker --skill reviewer
  [ "$status" -eq 0 ]
  [ -d "$SAGE_HOME/agents/worker" ]
  # skill should be recorded in agent config
  [ -f "$SAGE_HOME/agents/worker/skills.json" ]
  run cat "$SAGE_HOME/agents/worker/skills.json"
  [[ "$output" == *"reviewer"* ]]
}

@test "create with --skill fails for nonexistent skill" {
  run sage create worker --skill nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
