# SageCLI Refactor Audit — 2026-04-23

**TL;DR**: Don't split the file yet. But do surgically refactor 4 giant functions (1,337 lines = 16% of file). ROI on splitting into modules is low; ROI on shrinking the top 4 functions is high.

## Shape of the Codebase

| Metric | Value |
|---|---|
| Total lines | 8,503 |
| Total functions | 130 |
| Commands (`cmd_*`) | 61 |
| Helpers (`_*`) | 69 |
| Tests | 928 (across 154 `.bats` files) |
| Avg function length | 65 lines |

### Function size distribution

| Bucket | Count | % | Verdict |
|---|--:|--:|---|
| ≤20 lines | 31 | 24% | ✅ Healthy dispatchers & utils |
| 21–50 lines | 32 | 25% | ✅ Normal bash cmd handlers |
| 51–100 lines | 39 | 30% | ⚠ Tolerable but watch |
| 101–200 lines | 16 | 12% | 🟠 Review for split opportunities |
| >200 lines | **4** | 3% | 🔴 **Definitely refactor** |

**75% of functions are ≤100 lines** — the file is not, on average, a mess. The pain is concentrated.

## The Top 4 Offenders (1,337 lines, 16% of the file)

| # | Function | Lines | Max nesting | Tests | Priority |
|---|---|--:|--:|--:|---|
| 1 | `cmd_send` | **422** | 14 | 22 files | 🔴 Refactor |
| 2 | `cmd_plan` | 336 | (not measured — likely deep) | 6 files | 🟠 Extract sub-handlers |
| 3 | `_plan_execute` | 320 | 18 | 6 files | 🔴 Refactor (nesting=18 is pathological) |
| 4 | `_help_command` | 308 | low | 13 files | 🟢 Fine — it's just a big `case` statement |

### Why these matter

- **Nesting=18 in `_plan_execute`**: this is a debugger's nightmare. Each level is an `if/for/while/case` — stack traces in bash don't exist, so this function is untestable in isolation today. The 6 `.bats` files testing it exercise it via CLI only.
- **`cmd_send` at 422 lines**: handles plain send, `--headless`, `--json`, `--force`, `--then` chaining, `--strict` retry, `--max-turns`, `--timeout`. These are 7 orthogonal concerns tangled into one function.

## Duplication Hotspots

Looking for repeated blocks of ≥8 identical lines across the file:

| Pattern | Occurrences | Refactor? |
|---|--:|---|
| `while [[ $# -gt 0 ]]; do` (arg parsing) | 29 | ⚪ No — each has different flags |
| `local agent_dir="$AGENTS_DIR/$name"` | 14 | ⚪ No — one-liner, clear |
| `if [[ -n "$reply_dir" ]]; then` | 12 | 🟡 Maybe — extract `_ensure_reply_dir` |
| `for agent_dir in "$AGENTS_DIR"/*/; do` | 8 | 🟡 Maybe — extract `_for_each_agent` iterator |
| `mkdir -p "$reply_dir"` | 8 | ⚪ No — trivial |

**Verdict**: no screaming duplication. Mostly coincidental overlap from similar patterns.

## Command "Importance" Ranking (by test coverage as proxy for user-facing value)

| Command | Test files | Weight |
|---|--:|---|
| `cmd_send` | 22 | 🔴 Core |
| `cmd_help` | 13 | 🔴 Core |
| `cmd_ls` | 10 | 🟠 Core |
| `cmd_history` | 9 | 🟠 Core |
| `cmd_plan` | 6 | 🟠 Core |
| `cmd_skill` | 4 | 🟡 Feature |
| `cmd_mcp` | 4 | 🟡 Feature |
| `cmd_trace` | 4 | 🟡 Feature |
| `cmd_wait` | 2 | 🟢 Edge |
| `cmd_task` | 1 | 🟢 Edge |
| `cmd_watch` | 1 | 🟢 Edge |

Every 61 `cmd_*` function has at least some test coverage. There is **no dead code** we can safely delete.

## Do we need a refactor? (Honest answer)

### What a *file split* would cost
- **Effort**: 2–3 days to split `sage` into `sage.core`, `sage.plan`, `sage.mcp`, `sage.skill`, etc., and a bootstrap loader
- **Risk**: 928 tests touch `$SAGE` binary path. Every test that sources helpers breaks
- **Benefit**: Better editor navigation — that's it. Bash doesn't care, CI doesn't care, users don't care

### What a *function-level* refactor would cost
- **Effort**: ~4 hours to split each of the Top 4 into 3–5 smaller helpers
- **Risk**: Low if done under existing tests (928 tests are our safety net)
- **Benefit**: Real — the improver is less likely to introduce bugs in `cmd_send` / `_plan_execute` if each concern is a named helper

## Recommendation

**Do not split the file. Do refactor the Top 4 functions in place.**

Prioritize:
1. **`cmd_send`** (422 lines, 22 test files) — extract `_send_headless`, `_send_strict_retry`, `_send_chain`. Tests protect us.
2. **`_plan_execute`** (320 lines, nesting=18) — extract `_wave_dispatch`, `_wave_collect`, `_wave_fail`. Highest bug risk in whole file.
3. `cmd_plan` (336) — extract `_plan_pattern_handler` per pattern (fan-out/pipeline/debate/map-reduce already modular in spirit)
4. `_help_command` (308) — leave alone, it's a declarative switch

**Do not do now**:
- File splitting (low ROI)
- Deduplication of `while [[ $# -gt 0 ]]` patterns (each is contextually different)
- Helper extraction from mid-size functions (51–200 line range is normal)

## Rules to codify in SKILL.md (for the improver)

When the improver picks refactor work later:
1. Never split a function that has no tests — add tests first
2. Preserve function names that appear in tests (rename breaks suite)
3. Any extraction must keep the full 928-test suite green
4. Target: no function >200 lines, no nesting >10
5. If a `cmd_*` function grows past 150 lines while adding a feature, split before committing

## Metrics to watch

Add to `sage stats` or a separate `sage doctor --code` someday:
- Max function length
- Max nesting depth
- Function count
- Test file count

No action on instrumentation now — just noted for later.

---

**Audit complete. No code changes in this step.** Next action is Step 1 (SKILL.md freeze rule), which can now reference this doc.
