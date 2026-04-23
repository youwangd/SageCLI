# SageCLI README Diagrams

Sources rendered with [PlantUML](https://plantuml.com) using the [markdown-viewer skills](https://github.com/markdown-viewer/skills) conventions (`mv-uml`, `mv-mindmap`).

| Diagram | Source | Used in |
|---|---|---|
| Architecture — message lifecycle | `architecture.puml` | `README.md` → `## Architecture` |
| Plan orchestrator — wave execution | `plan-waves.puml` | `README.md` → `## Plan Orchestrator` |
| Runtimes mindmap | `runtimes.puml` | `README.md` → `## Runtimes` |

## Regenerate

```bash
cd docs/diagrams
for f in *.puml; do
  plantuml -tsvg "$f"
  plantuml -tpng "$f"
done
```

Requires `plantuml` on `$PATH` (`java -jar plantuml.jar` wrapper is fine).
