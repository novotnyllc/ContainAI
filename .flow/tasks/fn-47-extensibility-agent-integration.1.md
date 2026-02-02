# fn-47-extensibility-agent-integration.1 Generic ACP Support - Remove hardcoded agent validation

## Description

Remove hardcoded agent validation from ACP proxy and shell wrapper. Currently only "claude" and "gemini" are allowed. Any agent name should be accepted. Add runtime validation with helpful errors and decouple image selection from agent selection.

### Core Problem

ACP is point-to-point: editor connects to one agent. The protocol has no discovery - it assumes you know which agent you want. So validation should be:
1. Accept any agent name
2. Fail gracefully if binary doesn't exist in container
3. Provide helpful error message

### Changes Required

1. **`src/acp-proxy/Program.cs:29-36`** - Remove hardcoded check:
   ```csharp
   // REMOVE THIS BLOCK:
   if (agent != "claude" && agent != "gemini")
   {
       await Console.Error.WriteLineAsync($"Unsupported agent: {agent}");
       return 1;
   }
   ```
   Keep test mode bypass (`CAI_ACP_TEST_MODE`).

2. **`src/containai.sh:3628-3634`** - Remove case statement validation:
   ```bash
   # REMOVE THIS:
   case "$agent" in
       claude|gemini) ;;
       *) printf '%s\n' "Unsupported agent: $agent" >&2; return 1 ;;
   esac
   ```

3. **`src/acp-proxy/Program.cs` (SpawnAgentProcess)** - Add runtime validation:
   - When `Process.Start()` fails, catch the exception
   - Return helpful error: "Agent 'foo' not found in container. Ensure the agent binary exists and supports --acp flag."

4. **Decouple image/agent selection** - These are separate concerns:
   - `--image-tag` / `CONTAINAI_IMAGE_TAG` → which Docker image to use
   - `--acp <agent>` → which binary to run inside container
   - `_CONTAINAI_AGENT_TAGS` in `container.sh:95-99` can remain for default image selection, but should not gate which agents can run

5. **`docs/acp.md`** - Update documentation (handled by Task 6)

### What NOT to do

- **No agent discovery** (`cai agents` listing) - YAGNI. Users know what they installed. If they try a missing agent, the error tells them.
- **No agent config file** - Agents are just binaries with `--acp` flag. No need for extra config.

### Testing

- `cai --acp nonexistent` → clear error: "Agent 'nonexistent' not found in container"
- `cai --acp claude` → works as before
- `cai --acp customagent` (with binary installed) → works

## Acceptance

- [ ] `cai --acp <any-name>` accepted without hardcoded validation
- [ ] Clear, helpful error when agent binary not found in container
- [ ] Image selection (`--image-tag`) independent of agent selection (`--acp`)
- [ ] Existing claude/gemini functionality unchanged
- [ ] Test added for generic agent support

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
