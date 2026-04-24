## sage bench report — run-20260424-100711

### Summary (per agent)

| Agent | Tasks | Success | Success rate | Median wall (ms) |
|-------|-------|---------|--------------|------------------|
| bench-claude | 5 | 3 | 60.0% | 46268 |
| bench-echo | 5 | 0 | 0.0% | 2057 |
| bench-ollama | 5 | 5 | 100.0% | 2577 |

### Per task × agent (wall_ms · success)

| Task | bench-claude | bench-echo | bench-ollama |
|------|------|------|------|
| 01-hello | 24685ms ✓ | 2644ms ✗ | 2577ms ✓ |
| 02-list | 46268ms ✓ | 2057ms ✗ | 2058ms ✓ |
| 03-math | 34252ms ✓ | 2057ms ✗ | 2057ms ✓ |
| 04-code-review | 301576ms ✗ | 2058ms ✗ | 26213ms ✓ |
| 05-json | 301666ms ✗ | 2057ms ✗ | 14153ms ✓ |
