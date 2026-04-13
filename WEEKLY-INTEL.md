# SageCLI Weekly Intelligence Report
**Week of**: 2026-04-07 → 2026-04-13 | **Generated**: 2026-04-13 12:00 UTC

---

## 1. Star Tracker

| Category | Project | Stars | Δ vs Last Week | Notes |
|----------|---------|------:|----------------|-------|
| **Top Agents** | opencode | 142,405 | +1,405 | Steady growth, 287 PRs merged (steipete tweet) |
| | cline | 60,213 | +213 | Kanban launch, CLI 2.0 maturing |
| | aider | 43,253 | +253 | Stable |
| | goose | 41,647 | +647 | Multi-LLM extensible |
| **Orchestrators** | ruflo (ex claude-flow) | 31,516 | +416 | Slowing from last week's +9.5K spike |
| | **claude-code-router** | **32,125** | **🆕 NEW** | Routes Claude Code to any LLM provider — proxy pattern |
| | gastown | 13,942 | -58 | Flat/declining |
| | claude-squad | 6,982 | -18 | Flat |
| | emdash (YC W26) | 3,847 | +47 | Slow growth post-launch |
| | aws/cli-agent-orchestrator | 457 | +6 | Minimal traction |
| | kodo | 57 | — | Dead |
| **Session Mgrs** | crystal (nimbalyst) | 3,017 | +17 | Desktop pivot |
| | toad | 2,848 | +48 | Unified terminal AI |
| | mux (Coder) | 1,635 | +35 | Desktop parallel dev |
| **Lists** | awesome-cli-coding-agents | 179 | +4 | Sage PR #47 still pending |
| **Us** | **SageCLI** | **1** | **0** | Adoption remains the bottleneck |

### Key Movement
- **claude-code-router** is the week's biggest surprise — 32K stars for a proxy that lets you use Claude Code's UI with any LLM backend. Not a direct competitor (it's infrastructure, not orchestration) but validates the "bring your own model" thesis that sage already supports via 8 runtimes.
- **ruflo** growth decelerated sharply (416 vs 9,500 last week) — the rebrand hype is fading.
- **gastown** declining — persistent work tracking alone isn't enough.

---

## 2. New Projects & Releases This Week

### claude-code-router (32K stars) — 🆕 WATCH
Transparent proxy that intercepts Claude Code API calls and routes to any LLM provider (OpenRouter, local models, etc.). Lets you use Claude Code's polished UI without paying Anthropic API costs.
- **Sage overlap**: sage already supports 8 runtimes natively — no proxy needed
- **Threat level**: LOW for orchestration, but HIGH for mindshare — people searching "use Claude Code with other models" find this, not sage

### OpenClaw / opencode experiments (steipete)
steipete tweeted about two experiments in next opencode release:
1. **Strict mode** — `executionContract = "strict-agentic"` forces GPT-5.x to keep working instead of being lazy
2. **Native Codex as harness** — Codex owns threads, resume, compaction
- **Sage overlap**: sage has `--max-turns` and `--retry` for persistence ✅, but no "strict mode" equivalent that instructs the model itself

### Cline Kanban Launch
Cline shipped a CLI-agnostic Kanban app for multi-agent task visualization. Blog post positions it as "real work isn't a flat list."
- **Sage overlap**: sage has `plan --show` for wave visualization ✅ and `dashboard --live` ✅, but no persistent Kanban board

### Claude Code Agent Teams — Docs Updated
Official docs at code.claude.com/docs/en/agent-teams now document limitations: "known limitations around session resumption, task coordination, and shutdown behavior."
- **Sage overlap**: sage handles all three (checkpoint/restore, msg/context, recover) ✅ — this is a selling point

### Anthropic Managed Agent Runtime (API)
r/ExperiencedDevs thread: "Anthropic launched a managed agent runtime as an API. Anyone evaluating build vs buy?"
- **Sage counter**: sage is the "build" option — zero vendor lock-in, runs anywhere

---

## 3. Community Buzz

### Hacker News
- **"How We Broke Top AI Agent Benchmarks"** (417 pts, 104 comments) — Berkeley paper on benchmark gaming. Relevant: agent orchestrators that claim benchmark wins may be overfitting.
- **"Do you trust AI agents with API keys?"** (8 pts, 8 comments) — Security concern growing. sage's `--timeout` and `--max-turns` guardrails are relevant but not sufficient — no key scoping.

### Reddit
- **r/ExperiencedDevs: "Coping with agentic workflow adoption"** — Experienced devs struggling with agent adoption. Terminal-first tools like sage lower the barrier vs IDE-heavy solutions.
- **r/ExperiencedDevs: Anthropic managed agent runtime** — Build vs buy debate. sage is pure "build" — zero dependencies, self-hosted.
- **r/LocalLLaMA: "Open source agent stack that actually works in 2026"** — Thread about working local agent setups. sage's ollama/llama-cpp runtimes are directly relevant but sage isn't mentioned.
- **r/ClaudeAI: "Multi-agent orchestration is the future"** — Top comment: "All you need is a good Claude.md and a prompt." Pushback against complex orchestrators. sage's simplicity (bash, no framework) is actually aligned with this sentiment.

### X/Twitter
- **@steipete** (opencode/openclaw): Shipping plugin harnesses — Codex as native harness, strict execution mode. 1,570 ❤️ on the strict mode tweet. Signal: model-level execution guarantees are in demand.
- **@kitlangton** (opencode creator): 287 PRs merged — opencode velocity is insane.
- **@rauchg** (Vercel): Vercel Sandbox as fastest microVM — "coding agents" mentioned as a use case. Cloud sandboxes are the next battleground.
- **@badlogicgames**: "down with context7" — pushback against MCP context servers. Contrarian signal.

---

## 4. Protocol & Platform Changes

### ACP (Agent Client Protocol)
- JetBrains ACP page live with install docs for custom agents
- Zed ACP integration with Tree-sitter semantic intelligence
- Kiro CLI has ACP docs at kiro.dev/docs/cli/acp/
- **Sage status**: ACP support shipped ✅ — sage is one of few CLI tools with ACP

### Claude Code
- Homebrew install channels split: `claude-code` (stable) vs `claude-code@latest`
- Claude Haiku 3 deprecation April 19 — migrate to Haiku 4.5
- Agent Teams docs updated with known limitations

### OpenCode
- Interrupted bash commands now keep final output (quality-of-life fix)
- clangd project root detection fix for C/C++
- SDK releases for Go

### MCP Ecosystem
- 6,900+ MCP servers tracked (PopularAiTools directory)
- "50 Best MCP Servers in 2026" listicle — sage's MCP management (`mcp add/ls/rm`) is a differentiator vs tools that require manual config

---

## 5. Actionable Insights for SageCLI

### What sage already has (no action needed)
| Competitor Feature | Sage Equivalent |
|---|---|
| ruflo multi-runtime | 8 runtimes (bash, claude-code, cline, gemini-cli, codex, kiro, ollama, llama-cpp) ✅ |
| Claude Code Agent Teams | `plan --pattern fan-out/pipeline/debate/map-reduce` ✅ |
| Session resumption | `checkpoint`, `restore`, `recover` ✅ |
| Inter-agent messaging | `msg send/ls/clear` ✅ |
| Agent guardrails | `--timeout`, `--max-turns`, `--retry` ✅ |
| MCP management | `mcp add/ls/rm`, `create --mcp` ✅ |
| Local model support | ollama + llama-cpp runtimes ✅ |
| ACP protocol | Shipped ✅ |
| Headless/CI | `send --headless --json`, GitHub Action ✅ |

### New action items (things sage does NOT have)

| Priority | Action | Rationale |
|----------|--------|-----------|
| **P0** | Get listed on awesome-cli-coding-agents | PR #47 still pending — follow up or resubmit. Free visibility to 179+ stargazers |
| **P0** | Post to r/LocalLLaMA "open source agent stack" thread | Direct audience match — mention ollama/llama-cpp runtimes |
| **P1** | Add `--strict` flag for agent execution | steipete's strict mode got 1,570 ❤️ — demand for "don't be lazy" agent behavior. Could implement as retry-on-incomplete |
| **P1** | Add API key scoping / sandboxing | HN "trust agents with API keys" thread shows growing concern. sage has timeout but no key restriction |
| **P2** | Consider LLM proxy/router mode | claude-code-router at 32K stars proves demand. sage could add `sage proxy` to route any agent's API calls through a local proxy for cost control |
| **P2** | Persistent Kanban view in dashboard | Cline Kanban launch — `dashboard --live` exists but no persistent task board across sessions |
| **P3** | Watch integration with plan orchestrator | `sage watch` exists but doesn't auto-trigger plan re-runs — noted as incomplete in ROADMAP |

---

## Summary

**Market position**: sage has feature parity or superiority vs every competitor except in adoption (1 star vs 31K+ for ruflo). The product isn't the problem — discovery is.

**This week's biggest signal**: claude-code-router hitting 32K stars proves "use any model with any tool" is a massive demand. sage already does this natively with 8 runtimes but nobody knows.

**Top 3 priorities**:
1. Get on awesome-cli-coding-agents list (PR #47)
2. Post sage to r/LocalLLaMA and r/ClaudeAI with real use cases
3. Add `--strict` execution mode (high community demand signal)
