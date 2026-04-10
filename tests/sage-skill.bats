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

# ── skill show ──

@test "skill show displays skill details" {
  mkdir -p "$SAGE_HOME/skills/reviewer"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","version":"2.0.0","description":"Code review skill","system_prompt":"Review all code carefully"}
EOF
  run sage skill show reviewer
  [ "$status" -eq 0 ]
  [[ "$output" == *"reviewer"* ]]
  [[ "$output" == *"2.0.0"* ]]
  [[ "$output" == *"Code review skill"* ]]
  [[ "$output" == *"Review all code carefully"* ]]
}

@test "skill show fails for nonexistent skill" {
  run sage skill show ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "skill show requires argument" {
  run sage skill show
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

# ── skill prompt injection ──

@test "send --headless prepends skill system_prompt to message" {
  # Create a skill with system_prompt
  mkdir -p "$SAGE_HOME/skills/reviewer"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","version":"1.0.0","description":"Review","system_prompt":"You are a code reviewer. Be thorough."}
EOF

  # Create agent with skill attached and a runtime that echoes the message
  sage create worker --skill reviewer
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() {
  local msg="$2"
  echo "$msg" | jq -r '.payload.text'
}
RTEOF

  run sage send worker "check main.py" --headless
  [ "$status" -eq 0 ]
  # The output should contain both the system prompt and the user message
  [[ "$output" == *"You are a code reviewer"* ]]
  [[ "$output" == *"check main.py"* ]]
}

# ── skill run (template execution) ──

@test "skill run executes a named template" {
  mkdir -p "$SAGE_HOME/skills/reviewer/templates"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","version":"1.0.0","description":"Review","system_prompt":"You review code.","templates":{"quick":"Do a quick review of the changes","security":"Focus on security vulnerabilities"}}
EOF

  sage create worker --skill reviewer
  cat > "$SAGE_HOME/runtimes/bash.sh" << 'RTEOF'
runtime_start() { :; }
runtime_inject() {
  local msg="$2"
  echo "$msg" | jq -r '.payload.text'
}
RTEOF

  run sage skill run worker quick
  [ "$status" -eq 0 ]
  [[ "$output" == *"You review code"* ]]
  [[ "$output" == *"Do a quick review"* ]]
}

@test "skill run fails without agent argument" {
  run sage skill run
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* ]]
}

@test "skill run fails for agent without skill" {
  sage create worker
  run sage skill run worker quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"no skill"* ]]
}

@test "skill run fails for unknown template" {
  mkdir -p "$SAGE_HOME/skills/reviewer"
  cat > "$SAGE_HOME/skills/reviewer/skill.json" << 'EOF'
{"name":"reviewer","version":"1.0.0","description":"Review","system_prompt":"Review.","templates":{"quick":"Quick review"}}
EOF
  sage create worker --skill reviewer
  run sage skill run worker nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

# ── skill registry ──

@test "skill registry ls shows default registry" {
  run sage skill registry ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"youwangd/sage-skills"* ]]
}

@test "skill registry add adds a custom registry" {
  run sage skill registry add someuser/my-skills
  [ "$status" -eq 0 ]
  [[ "$output" == *"added"* ]]
  run sage skill registry ls
  [[ "$output" == *"someuser/my-skills"* ]]
}

@test "skill registry add rejects duplicates" {
  sage skill registry add someuser/my-skills
  run sage skill registry add someuser/my-skills
  [ "$status" -ne 0 ]
  [[ "$output" == *"already"* ]]
}

@test "skill registry rm removes a registry" {
  sage skill registry add someuser/my-skills
  run sage skill registry rm someuser/my-skills
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"* ]]
  run sage skill registry ls
  [[ "$output" != *"someuser/my-skills"* ]]
}

@test "skill registry rm fails for unknown registry" {
  run sage skill registry rm nonexistent/repo
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "skill registry requires subcommand" {
  run sage skill registry
  [ "$status" -ne 0 ]
  [[ "$output" == *"registry"* ]]
  [[ "$output" == *"usage"* ]]
}

# ── skill search ──

@test "skill search finds matching skills from local index" {
  mkdir -p "$SAGE_HOME/registries/youwangd-sage-skills"
  cat > "$SAGE_HOME/registries/youwangd-sage-skills/index.json" << 'EOF'
[{"name":"code-review-pro","repo":"youwangd/skill-code-review","description":"AI code review","tags":["review","quality"]},{"name":"test-writer","repo":"youwangd/skill-test-writer","description":"Generate tests","tags":["testing"]}]
EOF
  run sage skill search review
  [ "$status" -eq 0 ]
  [[ "$output" == *"code-review-pro"* ]]
  [[ "$output" != *"test-writer"* ]]
}

@test "skill search shows no results message" {
  mkdir -p "$SAGE_HOME/registries/youwangd-sage-skills"
  echo '[]' > "$SAGE_HOME/registries/youwangd-sage-skills/index.json"
  run sage skill search nonexistent
  [ "$status" -eq 0 ]
  [[ "$output" == *"no matching"* ]]
}

@test "skill search requires query" {
  run sage skill search
  [ "$status" -ne 0 ]
  [[ "$output" == *"search"* ]]
  [[ "$output" == *"usage"* ]]
}

# ── skill install from registry ──

@test "skill install bare name looks up registry" {
  mkdir -p "$SAGE_HOME/registries/youwangd-sage-skills"
  cat > "$SAGE_HOME/registries/youwangd-sage-skills/index.json" << 'EOF'
[{"name":"my-test-skill","repo":"youwangd/skill-test","description":"Test skill","tags":[]}]
EOF
  # This will fail because the repo doesn't exist, but it should TRY the registry lookup
  run sage skill install my-test-skill
  [ "$status" -ne 0 ]
  # Should attempt to clone from the registry repo, not complain about path
  [[ "$output" == *"clone"* ]] || [[ "$output" == *"youwangd/skill-test"* ]]
}
