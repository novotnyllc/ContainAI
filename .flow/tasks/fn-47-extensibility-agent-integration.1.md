# fn-47-extensibility-agent-integration.1 Generic ACP Support - Remove hardcoded agent validation

## Description

Remove hardcoded agent validation from ACP proxy and shell wrapper. Currently only "claude" and "gemini" are allowed. Any agent name should be accepted. Add runtime validation with helpful errors and decouple image selection from agent selection.

### Core Problem

ACP is point-to-point: editor connects to one agent. The protocol has no discovery - it assumes you know which agent you want. So validation should be:
1. Accept any agent name
2. Fail gracefully if binary doesn't exist in container
3. Provide helpful error message

### Changes Required

1. **`src/ContainAI.Acp/AcpProxy.cs:51-54`** - Remove hardcoded check in constructor:
   ```csharp
   // REMOVE THIS BLOCK:
   if (!testMode && agent != "claude" && agent != "gemini")
   {
       throw new ArgumentException($"Unsupported agent: {agent}", nameof(agent));
   }
   ```
   Keep test mode parameter for backwards compatibility.

2. **`src/ContainAI.Acp/Sessions/AgentSpawner.cs`** - Add container-side preflight check:
   When spawning via containerized mode (`cai exec`), wrap the command to detect missing agents.

   **IMPORTANT: Avoid shell injection** - Pass agent as positional parameter, not embedded in string:
   ```csharp
   // Safe: agent passed as $1, not interpolated into shell string
   // cai exec -- bash -lc 'command -v -- "$1" >/dev/null 2>&1 || { printf "Agent '\''%s'\'' not found in container\n" "$1" >&2; exit 127; }; exec "$1" --acp' -- <agent>
   ```
   This ensures:
   - Clear error message when agent binary doesn't exist inside the container
   - No shell injection risk from spaces/quotes in agent name

   For direct spawn mode, catch `Win32Exception` / `FileNotFoundException` from `Process.Start()`.

3. **`src/lib/container.sh:116-119`** - Relax `_containai_resolve_image()`:
   The validation `if [[ -z "${_CONTAINAI_AGENT_TAGS[$agent]:-}" ]]` should not fail for unknown agents.
   Instead, use a default tag ("latest") for any unknown agent. The validation happens at runtime when the agent binary is executed.

4. **`src/acp-proxy/Program.cs`** - Update help text:
   Change `"claude" or "gemini"` to `"any agent binary supporting --acp"` in the description.

5. **`docs/acp.md`** - Update documentation (handled by Task 6)

### What NOT to do

- **No agent discovery** (`cai agents` listing) - YAGNI. Users know what they installed. If they try a missing agent, the error tells them.
- **No agent config file** - Agents are just binaries with `--acp` flag. No need for extra config.

### Testing

Integration test in `tests/integration/`:
- Run `cai acp proxy nonexistent` and verify stderr contains "Agent 'nonexistent' not found"
- Test with agent names containing spaces/special chars (should not cause injection)
- Or add minimal test that exercises the code path

## Acceptance

- [ ] `cai --acp <any-name>` accepted without hardcoded validation
- [ ] `src/ContainAI.Acp/AcpProxy.cs` constructor accepts any agent name
- [ ] Container-side preflight check gives clear error for missing agents
- [ ] Preflight uses positional parameters (no shell injection risk)
- [ ] Direct spawn mode catches process start failures
- [ ] `_containai_resolve_image()` allows any agent name with default tag
- [ ] Clear, helpful error when agent binary not found in container
- [ ] Image selection (`--image-tag`) independent of agent selection (`--acp`)
- [ ] Existing claude/gemini functionality unchanged
- [ ] Integration test added

## Done summary
# Task fn-47-extensibility-agent-integration.1 Summary

## Generic ACP Support - Remove hardcoded agent validation

### Changes Made

1. **`src/ContainAI.Acp/AcpProxy.cs`** - Removed hardcoded agent validation from constructor
   - Deleted the check `if (!testMode && agent != "claude" && agent != "gemini")`
   - Updated docstring to reflect any agent binary supporting --acp flag

2. **`src/ContainAI.Acp/Sessions/AgentSpawner.cs`** - Added runtime validation
   - Added container-side preflight check using bash wrapper with `command -v`
   - Safe from shell injection: agent passed as $1 positional parameter
   - Added Win32Exception handling for direct spawn mode
   - Clear error message: "Agent 'X' not found in container"

3. **`src/lib/container.sh`** - Relaxed `_containai_resolve_image()`
   - Now accepts any agent name
   - Defaults to "latest" tag for unknown agents
   - Preserves agent-specific tags for claude/gemini

4. **`src/acp-proxy/Program.cs`** - Updated help text
   - Changed from "claude, gemini" to "any agent supporting --acp flag"

5. **`tests/integration/test-acp-proxy.sh`** - Added 3 new integration tests
   - Test 16: Generic agent support - accepts any name
   - Test 17: Generic agent support - clear error for missing agent
   - Test 18: Generic agent support - no shell injection

### Verification

- All 18 integration tests pass
- Shellcheck passes on modified shell scripts
- C# projects build without errors

### Acceptance Criteria Met

- [x] `cai --acp <any-name>` accepted without hardcoded validation
- [x] `src/ContainAI.Acp/AcpProxy.cs` constructor accepts any agent name
- [x] Container-side preflight check gives clear error for missing agents
- [x] Preflight uses positional parameters (no shell injection risk)
- [x] Direct spawn mode catches process start failures
- [x] `_containai_resolve_image()` allows any agent name with default tag
- [x] Clear, helpful error when agent binary not found in container
- [x] Image selection (`--image-tag`) independent of agent selection (`--acp`)
- [x] Existing claude/gemini functionality unchanged
- [x] Integration tests added
## Evidence
- Commits:
- Tests:
- PRs:
