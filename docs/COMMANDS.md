# Commands Reference

53 commands across 12 domains. Run `sage help` or `sage <command> --help` for inline reference.

```
AGENTS
  init [--force]                 Initialize ~/.sage/
  demo [--clean]                 Scaffold a 3-agent fan-out demo
  create <name> [flags]          Create agent (--runtime R, --agent A, --model M)
  start   [name|--all]           Start in tmux
  stop    [name|--all]           Stop (kills process group)
  restart [name|--all]           Restart
  status  [--json]               Tree view of agents
  ls                             List agents (-l, --json, --running, --stopped, --runtime, --sort)
  info <name>                    Show full agent configuration and status
  rename <old> <new>             Rename an agent
  clone <src> <dest>             Duplicate config (no state)
  diff <name|--all> [--stat]     Git changes in agent worktree(s)
  merge <name> [--dry-run]       Merge worktree branch back to parent
  export <name> [--output f]     Archive as tar.gz (or --format json)
  rm <name>                      Remove agent
  clean                          Remove stale files

MESSAGING & TASKS
  send <to> <msg|@file> [flags]  Fire-and-forget (--force, --then <agent> for chains,
                                  --fallback <agent> for vendor failover)
  call <to> <msg|@file> [secs]   Synchronous request/response
  tasks [name]                   List tasks (--json, --status)
  runs                           List active runs
  result <task-id>               Get task result
  replay [task-id]               Re-send a previous task
  wait <name|--all>              Wait for completion (--timeout N)
  peek <name> [--lines N]        Live tmux pane + workspace view
  steer <name> <msg> [--restart] Course-correct a running agent
  inbox [--json] [--clear]       Messages sent TO the CLI

PLAN ORCHESTRATOR
  plan <goal>                    Decompose a goal into dependency waves
  plan --pattern <p>             Swarm pattern: fan-out | pipeline | debate | map-reduce
  plan --run <file>              Execute a saved plan
  plan --resume <file>           Resume from failure point
  plan --recover                 Detect and resume interrupted plans
  plan --validate <file>         Validate YAML/JSON without executing
  plan --list                    Show saved plans

TASK TEMPLATES
  task --list                    Show available templates (review, test, spec, debug, ...)
  task <template> [files...]     Run a template (--message, --runtime, --timeout, --background)

BENCH
  bench run <tasks-dir> --agents A,B,C   Run the same tasks across N agents
  bench report [--format markdown|json|csv]   Decision-ready comparison
  bench ls                       List past runs

MCP + SKILLS + TOOLS
  mcp {add|ls|rm|tools}          Register MCP servers with lifecycle management
  skill {install|ls|rm|show|run} Install from URL/path/registry; auto-injects prompts
  tool {add|ls|rm|run|show}      Local-tool registry per agent

ACP REGISTRY
  acp ls [--json]                List agents in the ACP Registry
  acp show <id>                  Show agent metadata (distribution, description)
  acp install <id> [--as name]   Install an ACP-registry agent as a sage agent

MEMORY & CONTEXT & ENV
  memory {set|get|ls|rm|clear} <agent> [k] [v]   Per-agent persistent memory (auto-injected)
  context {set|get|ls|rm} [k] [v]                Shared context across all agents
  env {set|ls|rm|scope} <agent> [k] [v]          Per-agent environment variables

OBSERVABILITY
  stats [--json] [--agent N]     Aggregate or per-agent metrics (--since, --cost, --efficiency)
  logs <name> [-f|--clear]       View/tail/clear logs (also --all, --failed)
  trace [name] [--tree] [-n N]   Cross-agent interaction timeline + call hierarchy
  history [--agent a] [-n N]     Activity timeline (--prune, --json)
  dashboard [--json|--live]      Live TUI: status, log tailing, plan progress

LIFECYCLE & RECOVERY
  checkpoint <name|--all>        Save agent state to disk
  restore    [name|--all]        Resume agents after reboot
  recover    [--yes]             Fix orphaned/dead tmux sessions
  doctor     [--all|--security|--agents|--mcp] [--json]   Health check

INTER-AGENT MESSAGING
  msg {send|ls|clear} <from> <to>  Inter-agent messages (auto-injected into prompts)

PRODUCTIVITY
  alias {set|ls|rm} <n> [cmd]    Reusable command shortcuts
  config {set|get|ls|rm}         Persistent user defaults
  watch <dir> --agent <n>        File watcher: trigger agent on changes
  completions <bash|zsh>         Generate tab-completion scripts
  attach [name]                  Attach to tmux session directly
  upgrade [--check]              Self-update from GitHub
  version | help                 Self-explanatory
```
