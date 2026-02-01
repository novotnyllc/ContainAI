#!/usr/bin/env bash
# ==============================================================================
# Sync Test Helpers for E2E Testing
# ==============================================================================
# Reusable test infrastructure for sync E2E tests. Patterns adapted from
# test-sync-integration.sh.
#
# Usage: source this file in your test scripts
#   source "$(dirname "${BASH_SOURCE[0]}")/sync-test-helpers.sh"
#
# Provides:
# - Docker context selection (DinD vs host)
# - Fixture creation (minimal, full, per-agent)
# - Container management with labels
# - Volume management with labels
# - Path assertion helpers (volume + container)
# - Hermetic HOME/DOCKER_CONFIG preservation
# - Cleanup on exit (trap with labels)
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Directory Setup
# ==============================================================================
SYNC_TEST_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_TEST_REPO_ROOT="$(cd "$SYNC_TEST_HELPERS_DIR/../.." && pwd)"
SYNC_TEST_SRC_DIR="$SYNC_TEST_REPO_ROOT/src"

# ==============================================================================
# Docker Context Selection
# ==============================================================================
# Prefer containai-docker context when available; otherwise use current default
setup_docker_context() {
    local context=""
    if docker context inspect containai-docker >/dev/null 2>&1; then
        context="containai-docker"
    else
        context=$(docker context show 2>/dev/null || true)
    fi

    DOCKER_CMD=(docker)
    if [[ -n "$context" ]]; then
        DOCKER_CMD=(docker --context "$context")
    fi
}

# Check if Docker is available and running
# Returns: 0 = ok, 1 = daemon not running (fail), 2 = docker binary not found (skip)
check_docker_available() {
    if ! command -v docker &>/dev/null; then
        printf '%s\n' "[SKIP] docker binary not found - skipping integration tests"
        return 2
    fi

    setup_docker_context

    if ! "${DOCKER_CMD[@]}" info &>/dev/null; then
        printf '%s\n' "[WARN] docker daemon not running (docker info failed)" >&2
        printf '%s\n' "[FAIL] Cannot run integration tests without docker daemon" >&2
        return 1
    fi
    return 0
}

# ==============================================================================
# Test Run Identification
# ==============================================================================
# Each test run gets a unique ID for parallel-safe cleanup
SYNC_TEST_RUN_ID="sync-e2e-$(date +%s)-$$"

# Labels used to identify test resources for safe cleanup
SYNC_TEST_RESOURCE_LABEL="containai.sync-test=1"
SYNC_TEST_RUN_LABEL="containai.sync-test_run=${SYNC_TEST_RUN_ID}"

# ==============================================================================
# Hermetic Fixture Setup
# ==============================================================================
# Save real HOME before any overrides
SYNC_TEST_REAL_HOME="${REAL_HOME:-$HOME}"

# Fixture directory (initialized by init_fixture_home)
SYNC_TEST_FIXTURE_HOME=""

# Profile HOME directory (separate from fixture for --from tests)
# This prevents HOME==--from which triggers profile import detection
SYNC_TEST_PROFILE_HOME=""

# Preserve Docker config
export DOCKER_CONFIG="${DOCKER_CONFIG:-${SYNC_TEST_REAL_HOME}/.docker}"

# Initialize fixture home directory
# Creates a temp dir under real home for Docker Desktop file-sharing
init_fixture_home() {
    SYNC_TEST_FIXTURE_HOME=$(mktemp -d "${SYNC_TEST_REAL_HOME}/.containai-sync-test-XXXXXX")
    printf '%s\n' "$SYNC_TEST_FIXTURE_HOME"
}

# Initialize separate profile home (to avoid HOME == --from collision)
# This is needed because import.sh detects profile import when source_root == HOME
init_profile_home() {
    SYNC_TEST_PROFILE_HOME=$(mktemp -d "${SYNC_TEST_REAL_HOME}/.containai-profile-XXXXXX")
    printf '%s\n' "$SYNC_TEST_PROFILE_HOME"
}

# ==============================================================================
# Fixture Creators (Selective Creation)
# ==============================================================================
# Tests opt-in to what they need - no upfront creation of all dirs

# Create minimal fixture - just the directory
create_fixture_home() {
    if [[ -z "$SYNC_TEST_FIXTURE_HOME" ]]; then
        init_fixture_home >/dev/null
    fi
    printf '%s\n' "$SYNC_TEST_FIXTURE_HOME"
}

# Per-agent fixture helpers

create_claude_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.claude/plugins/cache/test-plugin"
    mkdir -p "$fixture/.claude/commands"
    mkdir -p "$fixture/.claude/agents"
    mkdir -p "$fixture/.claude/skills"
    mkdir -p "$fixture/.claude/hooks"

    # Use unique marker content for content verification
    printf '%s\n' '{"test": true, "_marker": "CLAUDE_JSON_MARKER"}' >"$fixture/.claude.json"
    printf '%s\n' '{"credentials": "test-creds", "_marker": "CREDENTIALS_MARKER"}' >"$fixture/.claude/.credentials.json"
    printf '%s\n' '{"settings": "test", "_marker": "SETTINGS_MARKER"}' >"$fixture/.claude/settings.json"
    printf '%s\n' '{"local": true, "_marker": "SETTINGS_LOCAL_MARKER"}' >"$fixture/.claude/settings.local.json"
    printf '%s\n' '{"plugin": "PLUGIN_MARKER"}' >"$fixture/.claude/plugins/cache/test-plugin/plugin.json"
    printf '%s\n' 'COMMAND_MARKER' >"$fixture/.claude/commands/command.txt"
    printf '%s\n' '{"agent": "AGENT_MARKER"}' >"$fixture/.claude/agents/agent.json"
    printf '%s\n' '{"skill": "SKILL_MARKER"}' >"$fixture/.claude/skills/skill.json"
    printf '%s\n' 'HOOK_MARKER' >"$fixture/.claude/hooks/hook.sh"
    printf '%s\n' '# Test CLAUDE.md (CLAUDE_MD_MARKER)' >"$fixture/.claude/CLAUDE.md"
}

create_codex_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.codex/skills/.system"
    mkdir -p "$fixture/.codex/skills/custom"

    # Use unique marker content for content verification
    printf '%s\n' '# Codex config - CODEX_CONFIG_MARKER' >"$fixture/.codex/config.toml"
    printf '%s\n' '{"auth": "test-auth", "_marker": "CODEX_AUTH_MARKER"}' >"$fixture/.codex/auth.json"
    printf '%s\n' '{"skill": "system"}' >"$fixture/.codex/skills/.system/hidden.json"
    printf '%s\n' '{"skill": "custom", "_marker": "CODEX_CUSTOM_MARKER"}' >"$fixture/.codex/skills/custom/user.json"
}

create_opencode_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/opencode/agents"
    mkdir -p "$fixture/.config/opencode/commands"
    mkdir -p "$fixture/.config/opencode/skills"
    mkdir -p "$fixture/.config/opencode/modes"
    mkdir -p "$fixture/.config/opencode/plugins"
    mkdir -p "$fixture/.local/share/opencode"

    # Use unique marker content for content verification
    printf '%s\n' '{"opencode": "config", "_marker": "OPENCODE_CONFIG_MARKER"}' >"$fixture/.config/opencode/opencode.json"
    printf '%s\n' '# Instructions (OPENCODE_INSTRUCTIONS_MARKER)' >"$fixture/.config/opencode/instructions.md"
    printf '%s\n' '{"agent": "opencode", "_marker": "OPENCODE_AGENT_MARKER"}' >"$fixture/.config/opencode/agents/agent.json"
    printf '%s\n' 'OPENCODE_COMMAND_MARKER' >"$fixture/.config/opencode/commands/command.txt"
    printf '%s\n' '{"skill": "opencode", "_marker": "OPENCODE_SKILL_MARKER"}' >"$fixture/.config/opencode/skills/skill.json"
    printf '%s\n' '{"mode": "opencode", "_marker": "OPENCODE_MODE_MARKER"}' >"$fixture/.config/opencode/modes/mode.json"
    printf '%s\n' '{"plugin": "opencode", "_marker": "OPENCODE_PLUGIN_MARKER"}' >"$fixture/.config/opencode/plugins/plugin.json"
    printf '%s\n' '{"auth": "test-auth", "_marker": "OPENCODE_AUTH_MARKER"}' >"$fixture/.local/share/opencode/auth.json"
}

create_pi_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.pi/agent/skills/.system"
    mkdir -p "$fixture/.pi/agent/skills/custom"
    mkdir -p "$fixture/.pi/agent/extensions"

    # Use unique marker content for content verification
    printf '%s\n' '{"settings": true, "_marker": "PI_SETTINGS_MARKER"}' >"$fixture/.pi/agent/settings.json"
    printf '%s\n' '{"models": "secret", "_marker": "PI_MODELS_MARKER"}' >"$fixture/.pi/agent/models.json"
    printf '%s\n' '{"keybindings": true, "_marker": "PI_KEYBINDINGS_MARKER"}' >"$fixture/.pi/agent/keybindings.json"
    printf '%s\n' '{}' >"$fixture/.pi/agent/skills/.system/hidden.json"
    printf '%s\n' '{"skill": "custom", "_marker": "PI_SKILL_MARKER"}' >"$fixture/.pi/agent/skills/custom/user.json"
    printf '%s\n' 'PI_EXTENSION_MARKER' >"$fixture/.pi/agent/extensions/ext.txt"
}

create_kimi_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.kimi"

    # Use unique marker content for content verification
    printf '%s\n' '# Kimi config - KIMI_CONFIG_MARKER' >"$fixture/.kimi/config.toml"
    printf '%s\n' '{"_marker": "KIMI_MCP_MARKER"}' >"$fixture/.kimi/mcp.json"
}

create_copilot_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.copilot/skills"

    # Use unique marker content for content verification
    printf '%s\n' '{"config": "test", "_marker": "COPILOT_CONFIG_MARKER"}' >"$fixture/.copilot/config.json"
    printf '%s\n' '{"mcp": "test", "_marker": "COPILOT_MCP_MARKER"}' >"$fixture/.copilot/mcp-config.json"
    printf '%s\n' '{"skill": "custom", "_marker": "COPILOT_SKILL_MARKER"}' >"$fixture/.copilot/skills/skill.json"
}

create_gemini_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.gemini"

    # Use unique marker content for content verification
    printf '%s\n' '{"accounts": "test", "_marker": "GEMINI_ACCOUNTS_MARKER"}' >"$fixture/.gemini/google_accounts.json"
    printf '%s\n' '{"oauth": "test", "_marker": "GEMINI_OAUTH_MARKER"}' >"$fixture/.gemini/oauth_creds.json"
    printf '%s\n' '{"settings": true, "_marker": "GEMINI_SETTINGS_MARKER"}' >"$fixture/.gemini/settings.json"
    printf '%s\n' '# Gemini MD (GEMINI_MD_MARKER)' >"$fixture/.gemini/GEMINI.md"
}

create_aider_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Use unique marker content for content verification
    printf '%s\n' 'model: gpt-4  # AIDER_CONF_MARKER' >"$fixture/.aider.conf.yml"
    printf '%s\n' 'settings: true  # AIDER_MODEL_MARKER' >"$fixture/.aider.model.settings.yml"
}

create_continue_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.continue"

    # Use unique marker content for content verification
    printf '%s\n' 'config: true  # CONTINUE_YAML_MARKER' >"$fixture/.continue/config.yaml"
    printf '%s\n' '{"continue": "config", "_marker": "CONTINUE_JSON_MARKER"}' >"$fixture/.continue/config.json"
}

create_cursor_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.cursor/rules"
    mkdir -p "$fixture/.cursor/extensions"

    # Use unique marker content for content verification
    printf '%s\n' '{"_marker": "CURSOR_MCP_MARKER"}' >"$fixture/.cursor/mcp.json"
    printf '%s\n' 'CURSOR_RULE_MARKER' >"$fixture/.cursor/rules/rule.mdc"
    printf '%s\n' 'CURSOR_EXTENSION_MARKER' >"$fixture/.cursor/extensions/ext.txt"
}

create_gh_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/gh"

    printf '%s\n' 'github.com:' >"$fixture/.config/gh/hosts.yml"
    printf '%s\n' '  oauth_token: test-token' >>"$fixture/.config/gh/hosts.yml"
    printf '%s\n' 'editor: vim' >"$fixture/.config/gh/config.yml"
}

create_git_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    cat >"$fixture/.gitconfig" <<'EOF'
[user]
    name = Test User
    email = test@example.com
[credential]
    helper = osxkeychain
[commit]
    gpgsign = true
[gpg]
    format = ssh
[alias]
    co = checkout
EOF

    printf '%s\n' '*.log' >"$fixture/.gitignore_global"
}

create_shell_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.bashrc.d"
    mkdir -p "$fixture/.oh-my-zsh/custom"

    printf '%s\n' 'alias ll="ls -la"' >"$fixture/.bash_aliases"
    printf '%s\n' 'export TEST_VAR="from_bashrc_d"' >"$fixture/.bashrc.d/test.sh"
    printf '%s\n' 'export PRIV_VAR="secret"' >"$fixture/.bashrc.d/secret.priv.sh"
    printf '%s\n' '# Custom zsh' >"$fixture/.zshrc"
    printf '%s\n' '# Custom zprofile' >"$fixture/.zprofile"
    printf '%s\n' '# Custom zshenv' >"$fixture/.zshenv"
    printf '%s\n' 'set editing-mode vi' >"$fixture/.inputrc"
    printf '%s\n' '# Custom plugin' >"$fixture/.oh-my-zsh/custom/custom.zsh"
}

create_tmux_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/tmux"
    mkdir -p "$fixture/.local/share/tmux/plugins/tpm"

    printf '%s\n' 'set -g prefix C-a' >"$fixture/.tmux.conf"
    printf '%s\n' 'set -g prefix C-a' >"$fixture/.config/tmux/tmux.conf"
    printf '%s\n' '# TPM' >"$fixture/.local/share/tmux/plugins/tpm/tpm"
}

create_vim_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.vim/colors"
    mkdir -p "$fixture/.config/nvim"

    printf '%s\n' 'set number' >"$fixture/.vimrc"
    printf '%s\n' '" Color scheme' >"$fixture/.vim/colors/custom.vim"
    printf '%s\n' 'set number' >"$fixture/.config/nvim/init.vim"
}

create_vscode_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.vscode-server/extensions/test-ext"
    mkdir -p "$fixture/.vscode-server/data/Machine"
    mkdir -p "$fixture/.vscode-server/data/User/mcp"
    mkdir -p "$fixture/.vscode-server/data/User/prompts"

    printf '%s\n' '{"ext": true}' >"$fixture/.vscode-server/extensions/test-ext/package.json"
    printf '%s\n' '{"machine": true}' >"$fixture/.vscode-server/data/Machine/settings.json"
    printf '%s\n' '{}' >"$fixture/.vscode-server/data/User/mcp/config.json"
}

create_fonts_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.local/share/fonts"

    # Create a small test font file (just placeholder data)
    printf '%s' "FONT" >"$fixture/.local/share/fonts/TestFont.ttf"
}

create_starship_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config"

    printf '%s\n' 'format = "$all"' >"$fixture/.config/starship.toml"
}

create_agents_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.agents"

    printf '%s\n' '# Shared agents' >"$fixture/.agents/README.md"
}

# Preset: "full" fixture with all agents (for coverage tests)
create_full_fixture() {
    create_fixture_home >/dev/null
    create_claude_fixture
    create_codex_fixture
    create_opencode_fixture
    create_pi_fixture
    create_kimi_fixture
    create_copilot_fixture
    create_gemini_fixture
    create_aider_fixture
    create_continue_fixture
    create_cursor_fixture
    create_gh_fixture
    create_git_fixture
    create_shell_fixture
    create_tmux_fixture
    create_vim_fixture
    create_vscode_fixture
    create_fonts_fixture
    create_starship_fixture
    create_agents_fixture
}

# Preset: "minimal" fixture with only Claude (for most tests)
create_minimal_fixture() {
    create_fixture_home >/dev/null
    create_claude_fixture
}

# ==============================================================================
# Container Management
# ==============================================================================
# Track resources for cleanup
declare -a SYNC_TEST_CONTAINERS_CREATED=()
declare -a SYNC_TEST_VOLUMES_CREATED=()

# Create a test container with labels and name prefix
# Usage: create_test_container NAME [DOCKER_ARGS...]
# Returns: container ID on stdout
create_test_container() {
    local name="${1:-}"
    shift || true

    if [[ -z "$name" ]]; then
        printf '%s\n' "[ERROR] Container name cannot be empty" >&2
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        printf '%s\n' "[ERROR] Container name must contain only alphanumeric, dash, underscore" >&2
        return 1
    fi

    local full_name="test-${name}-${SYNC_TEST_RUN_ID}"
    local container_id

    container_id=$("${DOCKER_CMD[@]}" create \
        --label "$SYNC_TEST_RESOURCE_LABEL" \
        --label "$SYNC_TEST_RUN_LABEL" \
        --name "$full_name" \
        "$@") || return 1

    SYNC_TEST_CONTAINERS_CREATED+=("$full_name")
    printf '%s\n' "$container_id"
}

# Create a test volume with labels
# Usage: create_test_volume NAME
# Returns: volume name on stdout
create_test_volume() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        printf '%s\n' "[ERROR] Volume name cannot be empty" >&2
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        printf '%s\n' "[ERROR] Volume name must contain only alphanumeric, dash, underscore" >&2
        return 1
    fi

    local full_name="test-${name}-${SYNC_TEST_RUN_ID}"

    "${DOCKER_CMD[@]}" volume create \
        --label "$SYNC_TEST_RESOURCE_LABEL" \
        --label "$SYNC_TEST_RUN_LABEL" \
        "$full_name" >/dev/null || return 1

    SYNC_TEST_VOLUMES_CREATED+=("$full_name")
    printf '%s\n' "$full_name"
}

# Start a test container
# Usage: start_test_container NAME
start_test_container() {
    local name="$1"
    "${DOCKER_CMD[@]}" start "$name" >/dev/null
}

# Stop a test container
# Usage: stop_test_container NAME
stop_test_container() {
    local name="$1"
    "${DOCKER_CMD[@]}" stop "$name" >/dev/null 2>&1 || true
}

# Execute command in a container
# Usage: exec_in_container CONTAINER CMD...
exec_in_container() {
    local container="$1"
    shift
    "${DOCKER_CMD[@]}" exec "$container" "$@"
}

# ==============================================================================
# Path Assertion Helpers
# ==============================================================================
# Current test container (set by tests)
SYNC_TEST_CONTAINER=""

# Volume path assertions (for /mnt/agent-data)
assert_file_exists_in_volume() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -f "/mnt/agent-data/$path"
}

assert_dir_exists_in_volume() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -d "/mnt/agent-data/$path"
}

assert_path_exists_in_volume() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -e "/mnt/agent-data/$path"
}

assert_path_not_exists_in_volume() {
    local path="$1"
    ! exec_in_container "$SYNC_TEST_CONTAINER" test -e "/mnt/agent-data/$path"
}

# Container path assertions (for ~/)
assert_path_exists_in_container() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -e "$path"
}

assert_file_exists_in_container() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -f "$path"
}

assert_dir_exists_in_container() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -d "$path"
}

assert_path_not_exists_in_container() {
    local path="$1"
    ! exec_in_container "$SYNC_TEST_CONTAINER" test -e "$path"
}

# Symlink assertions
assert_symlink_target() {
    local link="$1"
    local expected_target="$2"
    local actual
    actual=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "$link")
    [[ "$actual" == "$expected_target" ]]
}

assert_is_symlink() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" test -L "$path"
}

# Permission assertions
assert_permissions_in_volume() {
    local path="$1"
    local expected="$2"
    local actual
    actual=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/$path")
    [[ "$actual" == "$expected" ]]
}

assert_permissions_in_container() {
    local path="$1"
    local expected="$2"
    local actual
    actual=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "$path")
    [[ "$actual" == "$expected" ]]
}

# Content assertions
cat_from_volume() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" cat "/mnt/agent-data/$path"
}

cat_from_container() {
    local path="$1"
    exec_in_container "$SYNC_TEST_CONTAINER" cat "$path"
}

assert_file_contains() {
    local path="$1"
    local pattern="$2"
    exec_in_container "$SYNC_TEST_CONTAINER" grep -q -- "$pattern" "$path"
}

assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    ! exec_in_container "$SYNC_TEST_CONTAINER" grep -q -- "$pattern" "$path"
}

# Assert content was copied (not placeholders) by checking for marker
assert_content_marker_in_volume() {
    local path="$1"
    local marker="$2"
    local content
    content=$(cat_from_volume "$path" 2>/dev/null) || return 1
    [[ "$content" == *"$marker"* ]]
}

# Assert content was NOT copied (placeholders) by checking marker is absent
assert_no_content_marker_in_volume() {
    local path="$1"
    local marker="$2"
    local content
    content=$(cat_from_volume "$path" 2>/dev/null) || return 0  # missing file = no marker
    [[ "$content" != *"$marker"* ]]
}

# ==============================================================================
# Import Helpers
# ==============================================================================
# Run cai import with hermetic HOME override (profile import mode)
# Usage: run_cai_import [extra_args...]
run_cai_import() {
    HOME="$SYNC_TEST_FIXTURE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" "$@" 2>&1
}

# Run cai import with separate HOME and --from to avoid profile import detection
# This is the correct way to test --from imports: HOME != --from source
# Usage: run_cai_import_from [extra_args...]
# Requires: SYNC_TEST_DATA_VOLUME and SYNC_TEST_FIXTURE_HOME to be set
run_cai_import_from() {
    # Use a separate profile home dir to avoid HOME == --from collision
    # which would trigger profile import detection and skip secrets
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi
    HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" --from "$SYNC_TEST_FIXTURE_HOME" --data-volume "$SYNC_TEST_DATA_VOLUME" "$@" 2>&1
}

# Run cai import as profile import (HOME == source, no --from)
# This tests the profile import behavior where secrets become placeholders
# Usage: run_cai_import_profile [extra_args...]
run_cai_import_profile() {
    # $1=SRC_DIR, $2=DATA_VOLUME, $3+=extra args
    # After shift: $1=DATA_VOLUME, $2+=extra args
    HOME="$SYNC_TEST_FIXTURE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import --data-volume "$1" "${@:2}"' _ "$SYNC_TEST_SRC_DIR" "$SYNC_TEST_DATA_VOLUME" "$@" 2>&1
}

# ==============================================================================
# Cleanup
# ==============================================================================
cleanup_test_containers() {
    local container

    # First pass: remove by labels
    local labeled_containers
    labeled_containers=$("${DOCKER_CMD[@]}" ps -aq \
        --filter "label=$SYNC_TEST_RESOURCE_LABEL" \
        --filter "label=$SYNC_TEST_RUN_LABEL" 2>/dev/null || true)
    if [[ -n "$labeled_containers" ]]; then
        printf '%s\n' "$labeled_containers" | xargs "${DOCKER_CMD[@]}" stop 2>/dev/null || true
        printf '%s\n' "$labeled_containers" | xargs "${DOCKER_CMD[@]}" rm 2>/dev/null || true
    fi

    # Second pass: registered containers
    for container in "${SYNC_TEST_CONTAINERS_CREATED[@]}"; do
        "${DOCKER_CMD[@]}" stop -- "$container" 2>/dev/null || true
        "${DOCKER_CMD[@]}" rm -- "$container" 2>/dev/null || true
    done
}

cleanup_test_volumes() {
    local vol

    # First pass: remove by labels
    local labeled_volumes
    labeled_volumes=$("${DOCKER_CMD[@]}" volume ls -q \
        --filter "label=$SYNC_TEST_RESOURCE_LABEL" \
        --filter "label=$SYNC_TEST_RUN_LABEL" 2>/dev/null || true)
    if [[ -n "$labeled_volumes" ]]; then
        printf '%s\n' "$labeled_volumes" | xargs "${DOCKER_CMD[@]}" volume rm 2>/dev/null || true
    fi

    # Second pass: registered volumes
    for vol in "${SYNC_TEST_VOLUMES_CREATED[@]}"; do
        "${DOCKER_CMD[@]}" volume rm "$vol" 2>/dev/null || true
    done
}

cleanup_fixture_home() {
    if [[ -d "$SYNC_TEST_FIXTURE_HOME" && "$SYNC_TEST_FIXTURE_HOME" == "${SYNC_TEST_REAL_HOME}/.containai-sync-test-"* ]]; then
        rm -rf "$SYNC_TEST_FIXTURE_HOME" 2>/dev/null || true
    fi
    if [[ -d "$SYNC_TEST_PROFILE_HOME" && "$SYNC_TEST_PROFILE_HOME" == "${SYNC_TEST_REAL_HOME}/.containai-profile-"* ]]; then
        rm -rf "$SYNC_TEST_PROFILE_HOME" 2>/dev/null || true
    fi
}

cleanup_sync_test_resources() {
    cleanup_test_containers
    cleanup_test_volumes
    cleanup_fixture_home
}

# Set up cleanup trap (call from main test script)
setup_cleanup_trap() {
    trap cleanup_sync_test_resources EXIT
}

# ==============================================================================
# Test Output Helpers
# ==============================================================================
SYNC_TEST_FAILED=0

sync_test_pass() {
    printf '%s\n' "[PASS] $*"
}

sync_test_fail() {
    printf '%s\n' "[FAIL] $*" >&2
    SYNC_TEST_FAILED=1
}

sync_test_skip() {
    printf '%s\n' "[SKIP] $*"
}

sync_test_info() {
    printf '%s\n' "[INFO] $*"
}

sync_test_section() {
    printf '\n%s\n' "=== $* ==="
}

# ==============================================================================
# Image Detection
# ==============================================================================
# Allow CI to override image name; default to containai-test:latest for local runs
SYNC_TEST_IMAGE_NAME="${IMAGE_NAME:-containai-test:latest}"

# Check if test image exists
check_test_image() {
    if ! "${DOCKER_CMD[@]}" image inspect "$SYNC_TEST_IMAGE_NAME" &>/dev/null; then
        printf '%s\n' "[ERROR] Image $SYNC_TEST_IMAGE_NAME not found" >&2
        printf '%s\n' "[INFO] Run './src/build.sh' first to build the test image" >&2
        return 1
    fi
    return 0
}
