#!/usr/bin/env bash
# Setup VS Code tasks in container per-user location
# This is run automatically during container initialization

set -euo pipefail

# Create VS Code server settings directory
VSCODE_SERVER_DIR="${HOME}/.vscode-server/data/Machine"
mkdir -p "${VSCODE_SERVER_DIR}"

# Create tasks.json for VS Code Remote
TASKS_FILE="${VSCODE_SERVER_DIR}/tasks.json"

cat > "${TASKS_FILE}" << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Launch Copilot Agent",
      "type": "shell",
      "command": "/workspace/scripts/launchers/run-copilot",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": true,
        "clear": false
      },
      "group": {
        "kind": "build",
        "isDefault": false
      }
    },
    {
      "label": "Launch Codex Agent",
      "type": "shell",
      "command": "/workspace/scripts/launchers/run-codex",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": true,
        "clear": false
      },
      "group": {
        "kind": "build",
        "isDefault": false
      }
    },
    {
      "label": "Launch Claude Agent",
      "type": "shell",
      "command": "/workspace/scripts/launchers/run-claude",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": true,
        "clear": false
      },
      "group": {
        "kind": "build",
        "isDefault": false
      }
    },
    {
      "label": "Launch Agent (Custom)",
      "type": "shell",
      "command": "/workspace/scripts/launchers/launch-agent",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": true,
        "clear": false
      },
      "group": {
        "kind": "build",
        "isDefault": false
      }
    },
    {
      "label": "List Running Agents",
      "type": "shell",
      "command": "docker ps --filter 'label=coding-agent=true' --format 'table {{.Names}}\\t{{.Status}}\\t{{.Image}}'",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": false
      }
    },
    {
      "label": "Stop All Agents",
      "type": "shell",
      "command": "docker ps --filter 'label=coding-agent=true' --format '{{.Names}}' | xargs -r docker stop",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": false
      }
    },
    {
      "label": "Verify Prerequisites",
      "type": "shell",
      "command": "/workspace/scripts/verify-prerequisites.sh",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": false
      }
    },
    {
      "label": "Build All Agent Images",
      "type": "shell",
      "command": "/workspace/scripts/build/build-all.sh",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "dedicated",
        "showReuseMessage": false,
        "clear": false
      },
      "group": {
        "kind": "build",
        "isDefault": true
      }
    },
    {
      "label": "Run Integration Tests",
      "type": "shell",
      "command": "/workspace/scripts/test/integration-test.sh",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "dedicated",
        "showReuseMessage": false,
        "clear": false
      }
    },
    {
      "label": "Run Unit Tests",
      "type": "shell",
      "command": "/workspace/scripts/test/run-unit-tests.sh",
      "problemMatcher": [],
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": false
      }
    }
  ]
}
EOF

echo "✅ VS Code tasks configured in ${TASKS_FILE}"
