# SageCLI Weekly Intelligence Report
**Week of**: 2026-04-13 → 2026-04-19 | **Generated**: 2026-04-19 21:40 UTC

---

## Star Tracker

| Repo | Stars | Δ vs last wk | Category | Notes |
|------|-------|--------------|----------|-------|
| anomalyco/opencode | 145,980 | — | Top agent | Dominant (ACP-native) |
| cline/cline | 60,451 | — | Top agent | IDE-first |
| Aider-AI/aider | 43,575 | — | Top agent | Stable |
| block/goose | 42,728 | — | Top agent | Stable |
| musistudio/claude-code-router | 32,572 | +447 | Infrastructure | Growth slowing (was +32K in 1st week) |
| **ruvnet/claude-flow** | **32,436** | **NEW in tracker** | **Orchestrator** | **Biggest find this week — direct competitor** |
| steveyegge/gastown | 14,318 | ~stable | Orchestrator | Still declining off 14.5K peak |
| smtg-ai/claude-squad | 7,082 | ~stable | Orchestrator | tmux-based |
| generalaction/emdash | 3,975 | +~150 | Session mgr | YC W26, visual control panel |
| stravu/crystal | 3,021 | — | Session mgr | git-worktree approach |
| batrachianai/toad | 2,885 | — | Session mgr | |
| coder/mux | 1,660 | — | Session mgr | Multiplexer |
| awslabs/cli-agent-orchestrator | 485 | — | Orchestrator | AWS Labs official |
| bradAGI/awesome-cli-coding-agents | 231 | — | Infrastructure | **sage still not listed** |
| ikamensh/kodo | 61 | +2 | Orchestrator | Tiny |
| **youwangd/SageCLI** | **1** | **0** | **Our repo** | **Adoption gap vs 32K+ competitors** |
| generalaction/ORCH | NOT_FOUND | — | — | Repo deleted or renamed |

### Star leaderboard headline
**claude-flow at 32,436 stars** is the single biggest competitive surprise — I'd missed it in prior reports. ruvnet shipped a mature Claude Code multi-agent orchestrator with parallel execution, persistent memory, and task coordination. It's nearly tied with claude-code-router (32,572) as the #1 "middleware for Claude Code" layer. Combined they dwarf sage's reach.

---

## New Projects & Releases This Week

### 🔥 Claude Opus 4.7 (April 16, 2026)
Major model release: +13% on coding benchmarks, 3x vision resolution, 98.5% visual acuity.
- **Impact on sage**: sage's `--runtime claude-code` inherits this for free. No code changes needed.
- New `/ultrareview` feature inside Claude Code = multi-agent review pass baked in. Overlaps with sage's `plan --pattern debate`.

### 🔥 OpenAI Codex Desktop Major Update (April 16, 2026)
Computer Use, in-app browser, image gen, 90+ plugins, memory preview, longer-running automations, and **hooks mechanism**.
- **Gap for sage**: Codex hooks is a new extension point. Projects like "Loopndroll" (908 ❤️ tweet) already build on top of it. sage's `--on-done` / `--on-fail` callbacks are similar but sage has no equivalent of Codex's in-process hook registry.

### 🔥 Claude Code CLI → native binary (April 17, 2026)
Claude Code now spawns a native Claude Code binary instead of Node wrapper. Faster startup, smaller footprint.
- **Action**: sage's `claude-code` runtime adapter should be tested to ensure it still detects the new binary path correctly.

### 🆕 Cloudflare "Code Mode" (aiDotEngineer talk this week)
Threepointone + KentonVarda + mattzcarey paradigm: agents "inhabit the state machine" instead of just generating. Tool Search + Code Mode = agents manipulate structured state, not text.
- **Potential direction for sage**: This is a *conceptual* shift, not a tool. Watch closely — could redefine how `sage tool` / `sage call` are modeled.

### 🆕 OpenCode v1.4.7 (April 16, 2026)
Minor release: improved desktop session change loading in review panel, GitHub Copilot integration tweaks.
- Incremental. No big feature change.

### 🆕 ACP Registry RFD → Completed
Initial version of the ACP Registry released. Gives ACP clients a standard way to **discover** agents.
- **Big deal for sage**: sage supports ACP. Registering sage in the ACP Registry could be a direct path to distribution. **Action item.**

### 🆕 "Loopndroll" for Codex (908 ❤️, thsottiaux)
New Codex hook-based tool getting attention. Don't know what it does exactly yet — flagged for follow-up.

---

## Community Buzz (HN / Reddit / X)

### HN (low signal this week)
Only 2 relevant stories: terminal UI for NHL games, C++→Rust rewrite. No agent-orchestration traffic — unusual quiet week.

### Reddit highlights
- **r/LocalLLaMA**: `qwen3.6-35b-a3b + 8-bit quant + 64k ctx on MBP M5 Max 128GB = "as good as Claude" via OpenCode` — viral post. Local-model-via-OpenCode story is the week's dominant LocalLLaMA narrative.
  - **Relevance for sage**: sage has `ollama` + `llama-cpp` runtimes ✅. But OpenCode owns the mindshare. sage needs a "run qwen3.6 locally with sage" tutorial.
- **r/LocalLLaMA**: "whats the best harness/app to use my llm with?" — direct market-opportunity question. Answers in thread likely name OpenCode, Aider, Cline. **sage needs to be in that conversation.**
- **r/LocalLLaMA**: "Are you guys actually using local tool calling or is it a collective prank?" — signal that local tool-calling is still fragile. sage's `tool run` + ollama story could cut through.
- **r/ExperiencedDevs**: "How to mentor vibecoding junior?" — cultural question. sage's multi-agent guardrails (`--timeout`, `--max-turns`, `--allow-env`) could frame a "safe AI onboarding" story.

### X/Twitter
- **@thsottiaux (OpenAI)**: *"If you think Codex with GPT-5.4 is fast already… we have line of sight for at least an order of magnitude in speedups this year"* — 4,579 ❤️. Codex momentum is intense.
- **@thsottiaux**: praised Loopndroll (Codex hooks-based tool, 908 ❤️) and "OpenClaw" (518 ❤️) — *"in the future we are not just going to have one agent"* — direct multi-agent thesis validation. **This is sage's thesis.**
- **@aiDotEngineer**: Code Mode keynote + Future of MCP keynote — MCP is now described as "most successful AI integration protocol ever" (1yr old).
- **@badlogicgames (Mario Zechner)**: terse week, nothing sage-relevant.
- **@karpathy, @mitchellh, @dhh, @steipete**: no agent-orchestration posts surfaced in this digest. Quiet week from the usual heavyweights.

---

## Protocol & Platform Changes

| Protocol | Change | Impact on sage |
|----------|--------|----------------|
| **ACP (Agent Client Protocol)** | Registry RFD completed; agent discovery now standardized | sage should register in ACP Registry — low-cost distribution win |
| **MCP** | 1yr anniversary; Visual Studio Windows MCP docs (Mar 31); GoodData launched MCP Server for agentic analytics (Q1 2026); Virtual MCP server pattern emerging (Prefect) | sage has `mcp add/ls/rm` ✅. "Virtual MCP" composite pattern is new — potential `sage mcp compose` future feature |
| **Claude Code** | Native binary spawn (Apr 17); plugin install recovery from interrupted installs; Opus 4.7 integration | sage claude-code runtime inherits for free |
| **OpenCode** | v1.4.7 incremental; GitHub Copilot integration improvements | Incremental |
| **Codex** | Major Apr 16 update: hooks mechanism, Computer Use, in-app browser, 90+ plugins | sage codex runtime should surface Codex hooks; `--on-done`/`--on-fail` already partially cover this |
| **Agent Payments Protocol (AP2)** | Google pushing agentic commerce protocols | Out of sage's scope — dev-tools, not commerce |

---

## Actionable Insights for SageCLI

**Reminder**: the following items are NOT in CAPABILITIES.md. Anything that already exists has been filtered out.

### P0 — This week
1. **Register sage in ACP Registry** (RFD completed this week, initial version released). Low effort, direct distribution path. sage already implements ACP.
2. **Submit PR to `bradAGI/awesome-cli-coding-agents`** (231 ⭐) — still not listed. Last week's report flagged this too; verify status of prior PR if submitted.
3. **Post "Run qwen3.6 locally with sage" to r/LocalLLaMA** — riding this week's viral OpenCode+qwen3.6 thread. sage's `ollama` + `llama-cpp` runtimes ✅ already exist but have zero community awareness.

### P1 — Next 2 weeks
4. **Add `sage tool hook` subcommand** — Codex shipped hooks this week and community is building on them (Loopndroll 908 ❤️). sage has `--on-done`/`--on-fail` for task-level callbacks ✅ but no tool-level hook registry. Gap.
5. **`sage mcp compose`** — emerging "Virtual MCP" pattern (Prefect blog) combines multiple MCP servers into one endpoint. sage has `mcp add/ls/rm` ✅ but no composition. Would differentiate.
6. **`sage acp register`** — helper command to publish a sage-managed agent into the ACP Registry. Makes #1 a one-liner instead of a manual process.

### P2 — Strategic
7. **Counter-narrative to claude-code-router (32.5K ⭐)**: router proxies Claude Code API to *any* model. sage goes further: natively runs 8 different agent runtimes without a proxy. Write a comparison post: *"Why native runtimes beat proxies"*. Target r/ClaudeAI + HN.
8. **Counter-narrative to claude-flow (32.4K ⭐)**: claude-flow orchestrates Claude Code sessions only. sage orchestrates ANY runtime. This is the "portable orchestration" pitch — draft a blog post.
9. **Watch Cloudflare's "Code Mode" paradigm** — if it gains traction (agents inhabiting state machines, not generating text), sage's `tool`/`call`/`plan` model may need to adapt. Track for 2–3 weeks before acting.
10. **Local-model tutorial series** — r/LocalLLaMA is asking *"whats the best harness for my llm?"*. sage needs a definitive answer with video/blog. First mover advantage closing fast.

### Features NOT to pursue
- ❌ Another multi-agent review pass — Claude Opus 4.7 shipped `/ultrareview` natively. Don't compete; call it via `sage send` instead.
- ❌ Agent Payments Protocol integration — out of dev-tools scope.
- ❌ Kanban UI / visual board — last week's gap still stands but remains P2; `sage dashboard --live` ✅ covers 70%.

---

## Week-over-Week Deltas

| Signal | Last wk (Apr 7–13) | This wk (Apr 13–19) |
|--------|--------------------|---------------------|
| Biggest new entrant | claude-code-router (32,125 ⭐, fresh discovery) | **claude-flow (32,436 ⭐, another fresh discovery)** |
| Model release | none | **Claude Opus 4.7 (+13% coding)** |
| Codex signal | steipete strict mode (1.5K ❤️) | **Major Codex update + hooks (4.6K ❤️)** |
| Local-model momentum | Anthropic managed runtime | **qwen3.6+OpenCode viral on r/LocalLLaMA** |
| Protocol change | — | **ACP Registry released; Cloudflare Code Mode paradigm** |
| sage commands | 50 (mis-stated as 47) | 50 (no change) |
| sage stars | 1 | 1 |

**Theme of the week**: the orchestration layer is consolidating around Claude Code. Two 32K-star middleware projects (router + flow) now dominate that niche. sage's differentiator — *runtime-agnostic orchestration* — is more relevant than ever, but also harder to market because the air is filled with Claude-Code-specific tools.
