#!/usr/bin/env bash
# ==============================================================================
# Shell Customization Sync Tests
# ==============================================================================
# Tests sync for shell customization: .bashrc.d sourcing, .bash_aliases linked
# as ~/.bash_aliases_imported, .inputrc, zsh configs, oh-my-zsh/custom.
#
# Key test points:
# - .bashrc.d sourced from /mnt/agent-data/shell/bashrc.d (via bash -i -c)
# - .bashrc.d p flag excludes *.priv.* files (security)
# - .bash_aliases linked as ~/.bash_aliases_imported (different from source)
# - Aliases work in interactive container shell
# - .inputrc synced correctly
# - .zshrc, .zprofile, .zshenv synced correctly
# - .oh-my-zsh/custom synced with R flag
#
# Usage:
#   ./tests/integration/sync-tests/test-shell-sync.sh
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make tests hermetic: clear config discovery inputs to prevent developer's
# real config (e.g., ~/.config/containai/containai.toml) from affecting tests.
unset XDG_CONFIG_HOME 2>/dev/null || true

# Source test helpers
source "$SCRIPT_DIR/../sync-test-helpers.sh"

# ==============================================================================
# Early Guards
# ==============================================================================
docker_status=0
check_docker_available || docker_status=$?
if [[ "$docker_status" == "2" ]]; then
    exit 0
elif [[ "$docker_status" != "0" ]]; then
    exit 1
fi

if ! check_test_image; then
    exit 1
fi

# ==============================================================================
# Test Setup
# ==============================================================================
setup_cleanup_trap

init_fixture_home >/dev/null

sync_test_info "Fixture home: $SYNC_TEST_FIXTURE_HOME"
sync_test_info "Test image: $SYNC_TEST_IMAGE_NAME"

# Test counter for unique volume names
SYNC_TEST_COUNTER=0

# ==============================================================================
# Helper to run a test with a fresh container and volume
# ==============================================================================
# Each test gets its own fresh volume for isolation
# Usage: run_shell_sync_test NAME SETUP_FN TEST_FN [extra_import_args...]
run_shell_sync_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"
    shift 3

    local extra_import_args=()
    while [[ $# -gt 0 ]]; do
        extra_import_args+=("$1")
        shift
    done

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "shell-data-${SYNC_TEST_COUNTER}")

    # Create unique container for this test
    # Override entrypoint to bypass systemd (which requires Sysbox)
    # Use tail -f for portable keepalive
    create_test_container "$test_name" \
        --entrypoint /bin/bash \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" -c "tail -f /dev/null" >/dev/null

    # Set up fixture
    if [[ -n "$setup_fn" ]]; then
        "$setup_fn"
    fi

    # Run import and capture output/exit code
    if [[ ${#extra_import_args[@]} -gt 0 ]]; then
        import_output=$(run_cai_import_from "${extra_import_args[@]}" 2>&1) || import_exit=$?
    else
        import_output=$(run_cai_import_from 2>&1) || import_exit=$?
    fi
    if [[ $import_exit -ne 0 ]]; then
        sync_test_fail "$test_name: import failed (exit=$import_exit)"
        printf '%s\n' "$import_output" | head -20 >&2
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        # Clean up this test's container and volume
        "${DOCKER_CMD[@]}" rm -f "test-${test_name}-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        return
    fi

    # Start container
    start_test_container "test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Set current container for assertions
    SYNC_TEST_CONTAINER="test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Run init script to create symlinks (since we bypassed systemd)
    exec_in_container "$SYNC_TEST_CONTAINER" cai system init >/dev/null 2>&1 || true

    # Run test
    if "$test_fn"; then
        sync_test_pass "$test_name"
    else
        sync_test_fail "$test_name"
    fi

    # Stop container
    stop_test_container "test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Clean up this test's volume (for isolation)
    "${DOCKER_CMD[@]}" rm -f "test-${test_name}-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true

    # Clear fixture for next test
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 1: .bashrc.d sourced via bash -i -c (correct path)
# ==============================================================================
# This tests that scripts in .bashrc.d are sourced when running an interactive
# shell. The scripts land in /mnt/agent-data/shell/bashrc.d and are sourced
# via a hook in container's .bashrc.

setup_bashrc_d_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.bashrc.d"

    # Create a test script that sets an environment variable
    printf '%s\n' 'export BASHRC_D_TEST="sourced_from_volume"' >"$fixture/.bashrc.d/test-env.sh"
}

test_bashrc_d_sourced_assertions() {
    # Verify the file landed in the volume path
    assert_file_exists_in_volume "shell/bashrc.d/test-env.sh" || {
        printf '%s\n' "[DEBUG] shell/bashrc.d/test-env.sh not found in volume" >&2
        return 1
    }

    # Verify content is correct
    local content
    content=$(cat_from_volume "shell/bashrc.d/test-env.sh") || return 1
    if [[ "$content" != *"BASHRC_D_TEST"* ]]; then
        printf '%s\n' "[DEBUG] test-env.sh does not contain BASHRC_D_TEST" >&2
        return 1
    fi

    # Use bash -i -c (interactive) to verify scripts are sourced
    # The container's .bashrc has a hook that sources /mnt/agent-data/shell/bashrc.d/*.sh
    # Use sentinel pattern to handle potential .bashrc stdout noise
    local result
    result=$(exec_in_container "$SYNC_TEST_CONTAINER" bash -i -c 'printf "__BASHRC_D__%s\n" "${BASHRC_D_TEST:-}"' 2>/dev/null | grep '^__BASHRC_D__' | tail -n 1) || {
        printf '%s\n' "[DEBUG] Failed to run bash -i -c in container" >&2
        return 1
    }

    if [[ "$result" != "__BASHRC_D__sourced_from_volume" ]]; then
        printf '%s\n' "[DEBUG] BASHRC_D_TEST='$result', expected '__BASHRC_D__sourced_from_volume'" >&2
        printf '%s\n' "[DEBUG] .bashrc.d script not being sourced correctly" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 2: .bashrc.d *.priv.* files excluded (p flag)
# ==============================================================================
# The p flag in sync-manifest.toml excludes files matching *.priv.* for security.
# This prevents sensitive scripts from being synced to the container.

setup_bashrc_d_priv_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.bashrc.d"

    # Public script - should sync
    printf '%s\n' 'export PUBLIC_VAR="public_value"' >"$fixture/.bashrc.d/public.sh"

    # Private script with *.priv.* pattern - should be EXCLUDED
    printf '%s\n' 'export SECRET_VAR="secret_value"' >"$fixture/.bashrc.d/secrets.priv.sh"

    # Another format: .priv. in middle - should also be EXCLUDED
    printf '%s\n' 'export ANOTHER_SECRET="another_secret"' >"$fixture/.bashrc.d/keys.priv.env.sh"
}

test_bashrc_d_priv_filter_assertions() {
    # public.sh should sync
    assert_file_exists_in_volume "shell/bashrc.d/public.sh" || {
        printf '%s\n' "[DEBUG] public.sh should exist in volume" >&2
        return 1
    }

    # Verify public content
    local public_content
    public_content=$(cat_from_volume "shell/bashrc.d/public.sh") || return 1
    if [[ "$public_content" != *"PUBLIC_VAR"* ]]; then
        printf '%s\n' "[DEBUG] public.sh does not contain expected content" >&2
        return 1
    fi

    # secrets.priv.sh should be EXCLUDED (p flag)
    if assert_path_exists_in_volume "shell/bashrc.d/secrets.priv.sh" 2>/dev/null; then
        printf '%s\n' "[DEBUG] secrets.priv.sh should NOT exist (p flag excludes *.priv.*)" >&2
        return 1
    fi

    # keys.priv.env.sh should also be EXCLUDED
    if assert_path_exists_in_volume "shell/bashrc.d/keys.priv.env.sh" 2>/dev/null; then
        printf '%s\n' "[DEBUG] keys.priv.env.sh should NOT exist (p flag excludes *.priv.*)" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 3: .bash_aliases linked as ~/.bash_aliases_imported
# ==============================================================================
# The sync manifest specifies .bash_aliases -> shell/bash_aliases with
# container_link = ".bash_aliases_imported". This is intentionally different
# from the source name to preserve the user's original .bash_aliases if any.

setup_bash_aliases_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create .bash_aliases with a test alias
    printf '%s\n' 'alias testcmd="echo test_alias_works"' >"$fixture/.bash_aliases"
}

test_bash_aliases_linked_assertions() {
    # File should sync to shell/bash_aliases
    assert_file_exists_in_volume "shell/bash_aliases" || {
        printf '%s\n' "[DEBUG] shell/bash_aliases not found in volume" >&2
        return 1
    }

    # Container should have it linked as ~/.bash_aliases_imported (guarded for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.bash_aliases_imported" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.bash_aliases_imported" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/bash_aliases" ]]; then
        printf '%s\n' "[DEBUG] ~/.bash_aliases_imported symlink target='$actual_target', expected '/mnt/agent-data/shell/bash_aliases'" >&2
        return 1
    fi

    # Verify the alias content
    local alias_content
    alias_content=$(cat_from_volume "shell/bash_aliases") || return 1
    if [[ "$alias_content" != *"testcmd"* ]]; then
        printf '%s\n' "[DEBUG] bash_aliases does not contain testcmd alias" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 4: Alias works in interactive container shell
# ==============================================================================
# Verify that aliases defined in .bash_aliases actually work when running
# an interactive shell in the container.

setup_alias_works_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create alias that echoes a specific marker
    printf '%s\n' 'alias synctest="echo ALIAS_MARKER_12345"' >"$fixture/.bash_aliases"
}

test_alias_works_assertions() {
    # Verify the alias file exists
    assert_file_exists_in_volume "shell/bash_aliases" || return 1

    # Run the alias in an interactive shell
    # bash -i sources .bashrc which sources .bash_aliases_imported
    # Use tail -n 1 to handle potential .bashrc stdout noise
    local result
    result=$(exec_in_container "$SYNC_TEST_CONTAINER" bash -i -c 'synctest' 2>/dev/null | tail -n 1) || {
        printf '%s\n' "[DEBUG] Failed to run alias in interactive shell" >&2
        return 1
    }

    if [[ "$result" != "ALIAS_MARKER_12345" ]]; then
        printf '%s\n' "[DEBUG] Alias output='$result', expected 'ALIAS_MARKER_12345'" >&2
        printf '%s\n' "[DEBUG] Alias not working in interactive shell" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 5: .inputrc synced correctly
# ==============================================================================
# .inputrc controls readline behavior (keybindings, history settings).
# It should sync to shell/inputrc and be linked as ~/.inputrc.

setup_inputrc_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create .inputrc with custom readline settings
    {
        printf '%s\n' '# INPUTRC_TEST_MARKER'
        printf '%s\n' '"\e[A": history-search-backward'
        printf '%s\n' '"\e[B": history-search-forward'
        printf '%s\n' 'set editing-mode vi'
    } >"$fixture/.inputrc"
}

test_inputrc_synced_assertions() {
    # Verify file synced to volume
    assert_file_exists_in_volume "shell/inputrc" || {
        printf '%s\n' "[DEBUG] shell/inputrc not found in volume" >&2
        return 1
    }

    # Verify symlink in container (guarded for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.inputrc" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.inputrc" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/inputrc" ]]; then
        printf '%s\n' "[DEBUG] ~/.inputrc symlink target='$actual_target', expected '/mnt/agent-data/shell/inputrc'" >&2
        return 1
    fi

    # Verify content
    local content
    content=$(cat_from_volume "shell/inputrc") || return 1
    if [[ "$content" != *"INPUTRC_TEST_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] inputrc does not contain expected marker" >&2
        return 1
    fi
    if [[ "$content" != *"history-search-backward"* ]]; then
        printf '%s\n' "[DEBUG] inputrc does not contain expected keybinding" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 6: .zshrc synced correctly
# ==============================================================================
setup_zshrc_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create .zshrc with test content
    printf '%s\n' '# ZSHRC_TEST_MARKER' >"$fixture/.zshrc"
    printf '%s\n' 'export ZSH_VAR="zsh_value"' >>"$fixture/.zshrc"
}

test_zshrc_synced_assertions() {
    # Verify file synced to volume
    assert_file_exists_in_volume "shell/zshrc" || {
        printf '%s\n' "[DEBUG] shell/zshrc not found in volume" >&2
        return 1
    }

    # Verify symlink in container (guarded for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.zshrc" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.zshrc" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/zshrc" ]]; then
        printf '%s\n' "[DEBUG] ~/.zshrc symlink target='$actual_target', expected '/mnt/agent-data/shell/zshrc'" >&2
        return 1
    fi

    # Verify content
    local content
    content=$(cat_from_volume "shell/zshrc") || return 1
    if [[ "$content" != *"ZSHRC_TEST_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] zshrc does not contain expected marker" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 7: .zprofile synced correctly
# ==============================================================================
setup_zprofile_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create .zprofile with test content
    printf '%s\n' '# ZPROFILE_TEST_MARKER' >"$fixture/.zprofile"
    printf '%s\n' 'export ZPROFILE_VAR="zprofile_value"' >>"$fixture/.zprofile"
}

test_zprofile_synced_assertions() {
    # Verify file synced to volume
    assert_file_exists_in_volume "shell/zprofile" || {
        printf '%s\n' "[DEBUG] shell/zprofile not found in volume" >&2
        return 1
    }

    # Verify symlink in container (guarded for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.zprofile" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.zprofile" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/zprofile" ]]; then
        printf '%s\n' "[DEBUG] ~/.zprofile symlink target='$actual_target', expected '/mnt/agent-data/shell/zprofile'" >&2
        return 1
    fi

    # Verify content
    local content
    content=$(cat_from_volume "shell/zprofile") || return 1
    if [[ "$content" != *"ZPROFILE_TEST_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] zprofile does not contain expected marker" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 8: .zshenv synced correctly
# ==============================================================================
setup_zshenv_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    # Create .zshenv with test content
    printf '%s\n' '# ZSHENV_TEST_MARKER' >"$fixture/.zshenv"
    printf '%s\n' 'export ZSHENV_VAR="zshenv_value"' >>"$fixture/.zshenv"
}

test_zshenv_synced_assertions() {
    # Verify file synced to volume
    assert_file_exists_in_volume "shell/zshenv" || {
        printf '%s\n' "[DEBUG] shell/zshenv not found in volume" >&2
        return 1
    }

    # Verify symlink in container (guarded for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.zshenv" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.zshenv" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/zshenv" ]]; then
        printf '%s\n' "[DEBUG] ~/.zshenv symlink target='$actual_target', expected '/mnt/agent-data/shell/zshenv'" >&2
        return 1
    fi

    # Verify content
    local content
    content=$(cat_from_volume "shell/zshenv") || return 1
    if [[ "$content" != *"ZSHENV_TEST_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] zshenv does not contain expected marker" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 9: .oh-my-zsh/custom synced with R flag
# ==============================================================================
# The R flag means "remove existing first" - important for directories that
# may be pre-populated in the container image.

setup_ohmyzsh_custom_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.oh-my-zsh/custom/themes"
    mkdir -p "$fixture/.oh-my-zsh/custom/plugins/custom-plugin"

    # Create custom theme
    printf '%s\n' '# Custom theme - OHMYZSH_THEME_MARKER' >"$fixture/.oh-my-zsh/custom/themes/custom.zsh-theme"
    printf '%s\n' 'PROMPT="%n@%m %~ %# "' >>"$fixture/.oh-my-zsh/custom/themes/custom.zsh-theme"

    # Create custom plugin
    printf '%s\n' '# Custom plugin - OHMYZSH_PLUGIN_MARKER' >"$fixture/.oh-my-zsh/custom/plugins/custom-plugin/custom-plugin.plugin.zsh"

    # Create custom alias file
    printf '%s\n' '# Custom aliases - OHMYZSH_ALIAS_MARKER' >"$fixture/.oh-my-zsh/custom/aliases.zsh"
}

test_ohmyzsh_custom_synced_assertions() {
    # Verify directory synced to volume
    # Note: manifest says target = "shell/oh-my-zsh-custom" (with hyphen)
    assert_dir_exists_in_volume "shell/oh-my-zsh-custom" || {
        printf '%s\n' "[DEBUG] shell/oh-my-zsh-custom not found in volume" >&2
        return 1
    }

    # Verify theme synced
    assert_file_exists_in_volume "shell/oh-my-zsh-custom/themes/custom.zsh-theme" || {
        printf '%s\n' "[DEBUG] custom.zsh-theme not found in volume" >&2
        return 1
    }

    # Verify plugin synced
    assert_file_exists_in_volume "shell/oh-my-zsh-custom/plugins/custom-plugin/custom-plugin.plugin.zsh" || {
        printf '%s\n' "[DEBUG] custom plugin not found in volume" >&2
        return 1
    }

    # Verify aliases synced
    assert_file_exists_in_volume "shell/oh-my-zsh-custom/aliases.zsh" || {
        printf '%s\n' "[DEBUG] aliases.zsh not found in volume" >&2
        return 1
    }

    # Verify symlink in container (guarded check for set -e safety)
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.oh-my-zsh/custom" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Failed to read symlink ~/.oh-my-zsh/custom" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/oh-my-zsh-custom" ]]; then
        printf '%s\n' "[DEBUG] ~/.oh-my-zsh/custom symlink target='$actual_target', expected '/mnt/agent-data/shell/oh-my-zsh-custom'" >&2
        return 1
    fi

    # Verify content markers
    local theme_content
    theme_content=$(cat_from_volume "shell/oh-my-zsh-custom/themes/custom.zsh-theme") || return 1
    if [[ "$theme_content" != *"OHMYZSH_THEME_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] theme does not contain expected marker" >&2
        return 1
    fi

    # Verify plugin content marker
    local plugin_content
    plugin_content=$(cat_from_volume "shell/oh-my-zsh-custom/plugins/custom-plugin/custom-plugin.plugin.zsh") || return 1
    if [[ "$plugin_content" != *"OHMYZSH_PLUGIN_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] plugin does not contain expected marker" >&2
        return 1
    fi

    # Verify alias content marker
    local alias_content
    alias_content=$(cat_from_volume "shell/oh-my-zsh-custom/aliases.zsh") || return 1
    if [[ "$alias_content" != *"OHMYZSH_ALIAS_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] aliases does not contain expected marker" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 10: R flag replaces existing directory via link-repair
# ==============================================================================
# The R flag means "remove existing first" - verifies that native link-repair
# replaces a real directory at ~/.oh-my-zsh/custom with the correct symlink.
# This tests the repair mechanism directly (not restart-based, since repair
# is triggered by link-watcher on import timestamp change, not by restart).

setup_ohmyzsh_rflag_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.oh-my-zsh/custom"

    # Create content that should be synced
    printf '%s\n' '# RFLAG_SYNC_MARKER' >"$fixture/.oh-my-zsh/custom/synced.zsh"
}

test_ohmyzsh_rflag_assertions() {
    # Phase 1: Verify initial sync created the symlink
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.oh-my-zsh/custom" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Phase 1: Failed to read initial symlink ~/.oh-my-zsh/custom" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/oh-my-zsh-custom" ]]; then
        printf '%s\n' "[DEBUG] Phase 1: Unexpected initial symlink target='$actual_target'" >&2
        return 1
    fi

    # Phase 2: Replace symlink with real directory containing sentinel file
    # This simulates a scenario where something creates a real directory
    exec_in_container "$SYNC_TEST_CONTAINER" rm -f "/home/agent/.oh-my-zsh/custom" 2>/dev/null || true
    exec_in_container "$SYNC_TEST_CONTAINER" mkdir -p "/home/agent/.oh-my-zsh/custom" 2>/dev/null || {
        printf '%s\n' "[DEBUG] Phase 2: Failed to create real directory" >&2
        return 1
    }
    exec_in_container "$SYNC_TEST_CONTAINER" sh -c 'echo "SENTINEL_SHOULD_BE_GONE" > /home/agent/.oh-my-zsh/custom/sentinel.txt' 2>/dev/null || {
        printf '%s\n' "[DEBUG] Phase 2: Failed to create sentinel file" >&2
        return 1
    }

    # Verify sentinel exists
    if ! exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.oh-my-zsh/custom/sentinel.txt" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 2: Sentinel file not created" >&2
        return 1
    fi

    # Phase 3: Explicitly trigger native link repair to simulate repair mechanism
    # This is how the R flag is applied - repair removes existing and recreates symlink
    if ! exec_in_container "$SYNC_TEST_CONTAINER" cai system link-repair --fix --quiet 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 3: cai system link-repair failed" >&2
        return 1
    fi

    # Phase 4: Verify R flag behavior - symlink should be restored, sentinel gone
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.oh-my-zsh/custom" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Phase 4: ~/.oh-my-zsh/custom is not a symlink after repair (R flag failed)" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/shell/oh-my-zsh-custom" ]]; then
        printf '%s\n' "[DEBUG] Phase 4: Symlink target='$actual_target' after repair, expected volume path" >&2
        return 1
    fi

    # Verify sentinel is gone (was in the replaced real directory)
    if exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.oh-my-zsh/custom/sentinel.txt" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 4: Sentinel file still exists - R flag did not replace directory" >&2
        return 1
    fi

    # Verify synced content still accessible
    if ! exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.oh-my-zsh/custom/synced.zsh" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 4: Synced content not accessible after repair" >&2
        return 1
    fi

    return 0
}


# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "Shell Customization Sync Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    # Test 1: .bashrc.d sourced via bash -i -c (correct path)
    run_shell_sync_test "bashrc-d-sourced" setup_bashrc_d_fixture test_bashrc_d_sourced_assertions

    # Test 2: .bashrc.d *.priv.* files excluded (p flag)
    run_shell_sync_test "bashrc-d-priv" setup_bashrc_d_priv_fixture test_bashrc_d_priv_filter_assertions

    # Test 3: .bash_aliases linked as ~/.bash_aliases_imported
    run_shell_sync_test "bash-aliases" setup_bash_aliases_fixture test_bash_aliases_linked_assertions

    # Test 4: Alias works in interactive container shell
    run_shell_sync_test "alias-works" setup_alias_works_fixture test_alias_works_assertions

    # Test 5: .inputrc synced correctly
    run_shell_sync_test "inputrc-sync" setup_inputrc_fixture test_inputrc_synced_assertions

    # Test 6: .zshrc synced correctly
    run_shell_sync_test "zshrc-sync" setup_zshrc_fixture test_zshrc_synced_assertions

    # Test 7: .zprofile synced correctly
    run_shell_sync_test "zprofile-sync" setup_zprofile_fixture test_zprofile_synced_assertions

    # Test 8: .zshenv synced correctly
    run_shell_sync_test "zshenv-sync" setup_zshenv_fixture test_zshenv_synced_assertions

    # Test 9: .oh-my-zsh/custom synced with R flag
    # Note: R flag applies to symlink creation (rm -rf before ln -sfn), not volume sync.
    # The symlink replacement behavior is tested by the container image build process.
    # This test verifies content syncs correctly to the volume.
    run_shell_sync_test "ohmyzsh-custom" setup_ohmyzsh_custom_fixture test_ohmyzsh_custom_synced_assertions

    # Test 10: R flag replaces existing directory via link-repair
    run_shell_sync_test "ohmyzsh-rflag" setup_ohmyzsh_rflag_fixture test_ohmyzsh_rflag_assertions

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All shell customization sync tests passed"
        exit 0
    else
        sync_test_info "Some shell customization sync tests failed"
        exit 1
    fi
}

main "$@"
