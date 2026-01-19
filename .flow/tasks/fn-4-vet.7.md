# fn-4-vet.7 Create Python TOML parser (parse-toml.py)

<!-- Updated by plan-sync: fn-4-vet.4 already created parse-toml.py in agent-sandbox/ -->
<!-- This task may already be complete - verify existing implementation -->

## Description
Create `agent-sandbox/parse-toml.py` - a Python 3.11+ TOML config parser.

## Implementation

```python
#!/usr/bin/env python3
"""Parse ContainAI TOML config. Requires Python 3.11+ (tomllib)."""
import sys
import tomllib
import json
from pathlib import Path

def find_workspace(config: dict, workspace: str) -> dict | None:
    """Find workspace with longest matching path (segment boundary)."""
    workspace = Path(workspace).resolve()
    workspaces = config.get("workspace", {})
    
    best_match, best_len = None, 0
    for path_str, section in workspaces.items():
        cfg_path = Path(path_str)
        if not cfg_path.is_absolute():
            continue
        try:
            workspace.relative_to(cfg_path)
            if len(str(cfg_path)) > best_len:
                best_match, best_len = section, len(str(cfg_path))
        except ValueError:
            pass
    return best_match

def main():
    if len(sys.argv) < 3:
        print("Usage: parse-toml.py <config> <workspace>", file=sys.stderr)
        sys.exit(1)
    
    with open(sys.argv[1], "rb") as f:
        config = tomllib.load(f)
    
    ws = find_workspace(config, sys.argv[2])
    agent = config.get("agent", {})
    default_excludes = config.get("default_excludes", [])
    
    print(json.dumps({
        "data_volume": ws.get("data_volume") if ws else agent.get("data_volume", "sandbox-agent-data"),
        "excludes": list(set(default_excludes + (ws.get("excludes", []) if ws else [])))
    }))

if __name__ == "__main__":
    main()
```

## Key Points
- Exit 1 with stderr message if Python < 3.11 (tomllib import fails)
- Output JSON: `{"data_volume": "...", "excludes": [...]}`
- Absolute paths only in workspace sections (skip relative)
- Longest path-segment match wins
## Acceptance
- [ ] Script exists at `agent-sandbox/parse-toml.py`
- [ ] Requires Python 3.11+ (fails with clear error on older versions)
- [ ] Outputs valid JSON with `data_volume` and `excludes` keys
- [ ] Workspace matching uses path-segment boundaries
- [ ] Longest match wins when multiple workspaces match
- [ ] Excludes are cumulative (default_excludes + workspace excludes)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
