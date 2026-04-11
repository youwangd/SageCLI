# SageCLI Weekly Intelligence Report

**Week of**: 2026-04-07 → 2026-04-11 | **Generated**: 2026-04-11 07:35 UTC

---

## ⭐ Star Tracker

| Category | Project | Stars | Δ vs Last Week | Notes |
|----------|---------|------:|----------------|-------|
| **Top Agents** | opencode | 141,288 | — | Dominant. 141K and climbing |
| | cline | 60,147 | — | IDE-native, strong community |
| | aider | 43,145 | — | Terminal pair programming pioneer |
| | goose | 41,013 | — | Extensible, multi-LLM |
| **Orchestrators** | claude-flow (ruflo) | 31,163 | +9.5K vs 21.6K | 🔥 Massive growth — rebranded to ruflo, added Codex integration |
| | gastown | 13,847 | +1.3K vs 12.5K | Steady growth, persistent work tracking |
| | claude-squad | 6,942 | +542 vs 6.4K | Multi-agent tmux manager |
| | emdash | 3,818 | NEW | 🆕 YC W26 — open-source agentic dev env, parallel agents |
| | awslabs/cli-agent-orchestrator | 451 | +121 vs 330 | AWS official, hierarchical tmux |
| | kodo | 57 | NEW | Lightweight orchestrator for claude/codex/gemini |
| **Session Mgrs** | crystal (→ Nimbalyst) | 3,015 | ~flat | Rebranded to Nimbalyst, desktop app pivot |
| | toad | 2,821 | ~flat | Unified terminal AI interface |
| | mux (Coder) | 1,626 | NEW | Desktop app for isolated parallel dev |
| **Infrastructure** | claude-code-router | 31,957 | — | Use Claude Code as coding infra backbone |
| | awesome-cli-coding-agents | 166 | +29 vs 137 | Curated directory, mentions AgentPipe (98⭐), amux (56⭐) |
| **Us** | **SageCLI** | **1** | — | 🎯 Pure bash, zero-framework differentiator |

### Key Movements
- **claude-flow → ruflo**: Rebranded, now 31K stars. Added "enterprise-grade architecture, distributed swarm intelligence, RAG integration, and native Claude Code / Codex Integration." Growing fast.
- **emdash**: New YC W26 company at 3.8K stars. Open-source agentic dev env with parallel agents. Direct competitor.
- **Crystal → Nimbalyst**: Pivoted from CLI to desktop app. Less direct competition now.
- **Coder/mux**: Desktop app for isolated parallel agentic dev. 1.6K stars. Different approach (GUI vs CLI).

---

## 🆕 New Projects & Releases This Week

### Cline CLI 2.0 — Agent Control Plane (Feb 2026, gaining traction now)
Cline released CLI 2.0 turning the terminal into an "agent control plane" — bridging single-agent workflows to production-scale orchestration. This is exactly sage's territory.
- **Sage overlap**: sage already does multi-agent orchestration via `plan` command
- **Gap**: Cline has massive IDE user base (60K stars) funneling into CLI

### Cline Kanban — CLI-Agnostic Multi-Agent App
Cline announced Kanban: a CLI-agnostic app for multi-agent orchestration. Key quote: "the bottleneck isn't the AI; it's you. Your attention. Your cognitive bandwidth."
- **Sage overlap**: sage `plan` does wave-based dependency execution
- **Gap**: Kanban provides visual task board UI — sage is terminal-only

### Claude Code Agent Teams (Official)
Anthropic docs now have "Orchestrate teams of Claude Code sessions" — official multi-agent support with shared tasks, inter-agent messaging, centralized management.
- **Sage overlap**: sage already orchestrates Claude Code sessions
- **Threat level**: HIGH — platform-native multi-agent reduces need for external orchestrators

### Claude Code Custom Subagents (Official)
Anthropic docs: "Create and use specialized AI subagents in Claude Code for task-specific workflows."
- **Sage overlap**: sage `create --skill` provides task-specific workflows
- **Threat level**: MEDIUM — subagents are within a single session, sage orchestrates across sessions

### AgentPipe (98⭐) — Multi-Agent Chat Rooms
CLI/TUI app that orchestrates multi-agent conversations by enabling different AI CLI tools to communicate in shared rooms.
- **Sage gap**: sage doesn't have inter-agent messaging/chat rooms

### MCP Gateway Pattern Emerging
API7.ai published "What Is an MCP Gateway?" — infrastructure for managing, securing, and scaling MCP traffic in production. Azure MCP Server now built into VS 2026.
- **Sage overlap**: sage already has `mcp add/ls/rm` for MCP server management
- **Signal**: MCP is becoming enterprise infrastructure, not just dev tooling

### Gemini CLI (Google)
Google's open-source agent bringing Gemini to the terminal. Another runtime sage could support.
- **Sage opportunity**: Add `gemini-cli` as a runtime alongside claude-code, cline, kiro

---

## 📡 Community Buzz

### Hacker News
- **"I still prefer MCP over skills"** (262 pts, 227 comments) — Hot debate on MCP vs skills systems. Relevant because sage supports both (`mcp` and `skill` commands). Community sentiment: MCP is winning for tool integration, skills better for workflow templates.
- **Marimo Pair** (34 pts) — Reactive Python notebooks as environments for agents. Niche but interesting: notebook-as-agent-env pattern.

### Reddit
- **r/LocalLLaMA**: "I no longer need a cloud LLM to do quick web research" (tagged mcp) — local LLMs + MCP servers replacing cloud APIs. Validates sage's runtime-agnostic approach.
- **r/LocalLLaMA**: 9B agentic data analyst model (89% workflow completion) — small models becoming viable for agent tasks. Sage should work with local models.
- **r/LocalLLaMA**: gemma-4-26B with coding agent "Kon" — new coding agents appearing weekly.
- **r/MachineLearning**: "Video series on building orchestration layer for LLM post-training" — orchestration is hot topic beyond just coding.
- **r/ClaudeAI**: "How I Built a Multi-Agent Orchestration System with Claude Code" — community building DIY orchestration. These are sage's target users.

### X/Twitter
- **@karpathy**: "Growing gap in understanding of AI capability" — people underestimate current agentic models. Validates building agent tooling.
- **@mitchellh** (Ghostty): "I need a hardware device I can physically punch to stop the agentic session" (3.2K ❤️) — Agent runaway is a real UX problem. **Sage already has `--timeout` and `--max-turns` guardrails.**
- **@steipete**: "Anthropic's random system prompt blockers are getting weirder" (375 ❤️) — Friction with Claude Code's guardrails. Opportunity for sage to provide smoother orchestration layer.
- **@badlogicgames** (Pi creator): "pi: the feature copying machine" — Pi actively copying features from competitors. Sage should watch Pi's feature velocity.
- **@kitlangton** (opencode creator): Active but no major announcements this week.
- **@burkeholland** (VSCode/Copilot): "write-a-prd skill → implement in Copilot CLI" — skills-first workflow gaining traction. Sage's skills system is well-positioned.
- **@thsottiaux** (Codex): New $100 plan, 2X limits, rapid growth. Codex becoming mainstream — sage should ensure Codex runtime support.
- **Tembo comparison**: "15 AI Coding Agents Compared" — sage not listed. Need visibility.

---

## 🔧 Protocol & Platform Changes

### Claude Code
- Homebrew install fix: cask release channels (stable vs latest)
- ctrl+e line navigation fix
- **Agent Teams**: Official multi-agent orchestration docs (see above)
- **Custom Subagents**: Official subagent creation docs

### OpenCode (141K stars)
- Interrupted bash commands now keep final output (better error handling)
- clangd project root fix for C/C++
- SDK releases: opencode-sdk-go active development

### ACP (Agent Client Protocol)
- JetBrains AI Assistant now supports ACP agent installation/management
- Zed editor: ACP integration with Gemini CLI as first integration
- OpenClaw multi-agent framework (March 2026): "Solves unreliable ACP communication, agent task-registration amnesia, and ambiguous timeout semantics"
- **Sage already supports ACP** — this validates the investment

### MCP Ecosystem
- Azure MCP Server built into Visual Studio 2026
- MCP Gateway pattern emerging (API7.ai) — production-grade MCP infrastructure
- Microsoft Foundry Agent + MCP Servers on Azure Functions
- "18 Best DevOps MCP Servers for 2026" — MCP ecosystem exploding

---

## 🎯 Actionable Insights for SageCLI

### HIGH PRIORITY

1. **Add Gemini CLI runtime** — Google's gemini-cli is open-source and growing. Sage already supports claude-code, cline, kiro, bash. Adding gemini-cli is low effort, high value.
   - sage already has: runtime abstraction (`create --runtime`)
   - gap: no gemini-cli runtime handler

2. **Add Codex runtime** — Codex is exploding ($100 plan, 2X limits). Users will want to orchestrate Codex sessions.
   - sage already has: runtime abstraction
   - gap: no codex runtime handler

3. **Counter Claude Code Agent Teams** — Anthropic's official multi-agent is the biggest threat. Sage's value prop must be: "orchestrate ANY agent, not just Claude Code."
   - sage already has: runtime-agnostic orchestration, plan system
   - action: Update README positioning to emphasize multi-runtime advantage over Claude-native teams

4. **Get listed on awesome-cli-coding-agents** — 166 stars, actively maintained by bradAGI. Sage is not listed. Submit PR immediately.
   - action: PR to add SageCLI under "Orchestrators / Harnesses" section

### MEDIUM PRIORITY

5. **Inter-agent messaging** — AgentPipe (98⭐) enables agents to communicate in shared rooms. Sage's `context` command shares data but not real-time messages.
   - sage already has: `context set/get` for shared state
   - gap: no real-time inter-agent communication channel

6. **Visual task board** — Cline Kanban shows demand for visual orchestration. Sage is terminal-only.
   - sage already has: `plan` with wave-based execution, `status` for monitoring
   - gap: no visual/web UI for task orchestration

7. **Codex integration in orchestrators** — ruflo (claude-flow) added native Codex integration. This is becoming table stakes.
   - overlaps with item #2 above

### LOWER PRIORITY

8. **MCP Gateway awareness** — MCP is becoming enterprise infra. Sage's `mcp` command manages individual servers. Gateway pattern may matter later.
   - sage already has: `mcp add/ls/rm`, tool discovery
   - gap: no gateway/proxy concept (probably premature)

9. **Tembo/comparison site visibility** — Sage not listed in "15 AI Coding Agents Compared." Need to reach out or grow stars first.

### ALREADY COVERED (no action needed)
- ✅ Git worktree isolation (sage has `create --worktree`, `merge`)
- ✅ Headless/CI mode (sage has `send --headless`, `--json`, `action.yml`)
- ✅ MCP integration (sage has `mcp add/ls/rm`, `create --mcp`)
- ✅ Skills system (sage has `skill install/ls/rm/show/run`)
- ✅ Agent guardrails (sage has `--timeout`, `--max-turns`)
- ✅ ACP protocol support (sage has persistent sessions)
- ✅ Shared context (sage has `context set/get/ls/rm`)
- ✅ Agent export/import (sage has `export`, `create --from`)
- ✅ Plan orchestrator (sage has `plan` with wave dependencies)

---

*Next scan: 2026-04-18*
