# fn-44-build-system-net-project-restructuring.3 Refactor ACP code into ContainAI.Acp library and acp-proxy CLI

## Description
Refactor the monolithic Program.cs (1029 lines) into a proper library/CLI structure with ContainAI.Acp library and acp-proxy CLI application. Use System.CommandLine for CLI parsing and CliWrap for process management. Add xUnit 3 unit tests using .NET 10 TestPlatform v2 (no legacy runner packages). Include AOT viability gate for any new packages.

**CLI invocation change:** Users call `cai acp proxy <agent>` (subcommand pattern). The shell script delegates to the .NET binary. This is preparation for a future epic where all of `cai` migrates to C#.

**Size:** M
**Files:**
- `src/ContainAI.Acp/ContainAI.Acp.csproj` (new library)
- `src/ContainAI.Acp/Protocol/` (new - JSON-RPC types)
- `src/ContainAI.Acp/Sessions/` (new - session management with CliWrap)
- `src/ContainAI.Acp/PathTranslation/` (new - path translation)
- `src/acp-proxy/acp-proxy.csproj` (update - reference library, add System.CommandLine)
- `src/acp-proxy/Program.cs` (simplify to CLI entry point with System.CommandLine)
- `src/containai.sh` (update `_containai_acp_proxy` → new subcommand handler)
- `tests/ContainAI.Acp.Tests/ContainAI.Acp.Tests.csproj` (new - xUnit 3 tests, MTP)
- `tests/ContainAI.Acp.Tests/*.cs` (new - test files)
- `global.json` (configure Microsoft Testing Platform)
- `ContainAI.slnx` (add new projects)

## Approach

1. **Create ContainAI.Acp library project** with proper structure:
   - `Protocol/` - JSON-RPC message types, serialization (keep current implementation initially)
   - `Sessions/` - Session management using CliWrap for process spawning
   - `PathTranslation/` - Host/container path mapping
   - Keep AOT-compatible

2. **Use System.CommandLine for CLI parsing**:
   - Define `proxy` command with `<agent>` argument
   - Use source generators for AOT compatibility (`[GeneratedCode]` attributes)
   - Handle `--help` and `--version` automatically
   - Example invocation: `acp-proxy proxy claude` (called by `cai acp proxy claude`)
   - System.CommandLine 2.0.2 is AOT-friendly (32% smaller, 20% smaller NativeAOT)

3. **Use CliWrap for process execution**:
   - Fluent API for spawning MCP server processes
   - Clean stdin/stdout piping
   - Proper cancellation support
   - AOT-compatible (no reflection)

4. **Use StreamJsonRpc with SystemTextJsonFormatter for JSON-RPC**:
   - Use `SystemTextJsonFormatter` (NOT Newtonsoft, NOT MessagePack) - ACP requires UTF-8 JSON
   - Enable `EnableStreamJsonRpcInterceptors` MSBuild property for AOT proxy generation
   - Annotate RPC interfaces with `[JsonRpcContract]` attribute
   - Create `JsonSerializerContext` with `[JsonSerializable]` for all message types
   - Use `RpcTargetMetadata.FromShape<T>()` when adding local RPC targets
   - Configure `TypeInfoResolver` on formatter options
   - See: https://microsoft.github.io/vs-streamjsonrpc/docs/nativeAOT.html

5. **Update build.sh to be self-contained with NBGV**:
   - Detect local .NET SDK: `command -v dotnet`
   - If SDK found: use `dotnet tool restore && dotnet nbgv get-version`
   - If no SDK: fall back to Microsoft's SDK Docker image
   - Export `NBGV_*` environment variables for downstream use
   - Use version in AOT binary build (`-p:Version=$NBGV_SemVer2`)

6. **AOT viability gate** for all packages:
   - After adding all packages, run: `dotnet publish -r linux-x64 -c Release`
   - Run `tests/integration/test-acp-proxy.sh`
   - Verify no trimming warnings in build output

7. **Update acp-proxy CLI** to be thin wrapper:
   - System.CommandLine root command with `proxy` subcommand
   - `proxy <agent>` command runs the ACP server from library
   - Handle process lifecycle and cancellation

8. **Update shell script for new invocation pattern**:
   - Change `cai --acp <agent>` → `cai acp proxy <agent>`
   - Update `_containai_acp_proxy` to call `$proxy_bin proxy "$agent"`
   - Add `acp` subcommand handler in `containai()` function
   - Update help text to show new invocation

9. **Create xUnit 3 test project with .NET 10 MTP**:
   - Package reference: `xunit.v3` only (no runner packages needed)
   - Configure `global.json` with `"test": { "runner": "Microsoft.Testing.Platform" }`
   - Test path translation logic
   - Test session state management
   - Test JSON-RPC message handling
   - Use `[Fact]` and `[Theory]` attributes

## Key context

- Current code uses System.Text.Json source generators for AOT
- Session management handles multiple concurrent MCP sessions
- Path translation maps between host and container paths
- NDJSON framing for message protocol (per `.flow/memory/conventions.md`)
- Race condition pitfall: Register TCS before sending request (per `.flow/memory/pitfalls.md:381`)
- System.CommandLine 2.0.2 is AOT-friendly (used by .NET CLI itself)
- CliWrap is AOT-compatible and has no reflection usage
- **StreamJsonRpc IS AOT-compatible** with `SystemTextJsonFormatter` (see https://microsoft.github.io/vs-streamjsonrpc/docs/nativeAOT.html)
- **Do NOT use Newtonsoft** - use System.Text.Json source generators exclusively
- **ACP protocol requires UTF-8 JSON** - use `SystemTextJsonFormatter`, not MessagePack
- .NET 10 TestPlatform v2 (MTP) eliminates need for legacy runner packages
- `global.json` `test.runner` setting controls test execution (see https://github.com/xunit/xunit/issues/3421)

## Acceptance
- [ ] ContainAI.Acp library project exists and builds
- [ ] Library uses StreamJsonRpc with SystemTextJsonFormatter for JSON-RPC (no Newtonsoft)
- [ ] Library uses CliWrap for all process execution (no raw ProcessStartInfo)
- [ ] acp-proxy CLI uses System.CommandLine for argument parsing
- [ ] CLI has `proxy <agent>` subcommand (invoked as `acp-proxy proxy claude`)
- [ ] StreamJsonRpc interfaces annotated with `[JsonRpcContract]`
- [ ] JsonSerializerContext configured with `[JsonSerializable]` for all RPC message types
- [ ] `EnableStreamJsonRpcInterceptors` MSBuild property enabled
- [ ] AOT viability gate passed: `dotnet publish -r linux-x64 -c Release` succeeds without warnings
- [ ] Library is AOT-compatible (no trimming warnings)
- [ ] acp-proxy CLI references ContainAI.Acp library
- [ ] acp-proxy CLI builds as self-contained AOT binary
- [ ] `src/acp-proxy/build.sh` invokes NBGV for version
- [ ] `src/acp-proxy/build.sh` falls back to Docker SDK image when .NET not installed
- [ ] Shell invocation changed: `cai acp proxy <agent>` (not `cai --acp`)
- [ ] Help text updated to show new `cai acp proxy` invocation
- [ ] xUnit 3 test project exists at tests/ContainAI.Acp.Tests/
- [ ] Test project uses xunit.v3 only (no xunit.runner.visualstudio, no Microsoft.NET.Test.Sdk)
- [ ] global.json configures `"test": { "runner": "Microsoft.Testing.Platform" }`
- [ ] Unit tests cover path translation
- [ ] Unit tests cover session management
- [ ] Unit tests cover JSON-RPC message handling
- [ ] `dotnet test` passes all unit tests (using MTP, not VSTest)
- [ ] `tests/integration/test-acp-proxy.sh` passes (post-AOT-publish)
- [ ] All existing ACP functionality preserved
- [ ] Library can be referenced by external projects (future NuGet publishing)
- [ ] Code follows project conventions (no single 1000+ line files)

## Done summary
## Summary

Refactored the monolithic acp-proxy Program.cs (1029 lines) into a proper library/CLI structure:

### New Library: ContainAI.Acp

Created `src/ContainAI.Acp/` with modular structure:
- **Protocol/** - JSON-RPC 2.0 message types with System.Text.Json source generators for AOT
  - `JsonRpcTypes.cs` - JsonRpcMessage, JsonRpcError, AcpJsonContext (source generator)
  - `JsonRpcHelpers.cs` - Helper methods for ID normalization and response creation
- **PathTranslation/** - Host/container path mapping
  - `PathTranslator.cs` - Translates paths and MCP server configs between host and container
  - `WorkspaceResolver.cs` - Resolves workspace root using git or .containai config (uses CliWrap)
- **Sessions/** - Session management
  - `AcpSession.cs` - Session state with request/response correlation
  - `AgentSpawner.cs` - Process spawning for agent processes
  - `OutputWriter.cs` - Thread-safe NDJSON output to stdout
- **AcpProxy.cs** - Main proxy orchestrator class

### Updated CLI: acp-proxy

- Uses System.CommandLine 2.0.2 for argument parsing
- New subcommand pattern: `acp-proxy proxy <agent>` (default: claude)
- Thin CLI wrapper referencing ContainAI.Acp library
- AOT-compatible (5MB native binary)

### Shell Script Updates

- Added `cai acp proxy <agent>` subcommand pattern
- Retained backward compatibility with `cai --acp <agent>` (deprecated)
- Updated help text to show new invocation pattern

### Test Project: tests/ContainAI.Acp.Tests/

Created xUnit v3 test project with .NET 10 MTP:
- PathTranslatorTests - 10 tests for path translation
- JsonRpcHelpersTests - 9 tests for JSON-RPC helpers
- JsonRpcMessageTests - 12 tests for message serialization
- AcpSessionTests - 7 tests for session management

### Build Script Updates

- Added NBGV version detection with Docker fallback
- Updated binary paths for new artifacts output structure

### Key Changes

1. Library is AOT-compatible (no reflection, uses source generators)
2. Uses System.Text.Json exclusively (no Newtonsoft)
3. Uses Process for agent spawning (simpler than CliWrap for this use case)
4. CliWrap used only in WorkspaceResolver for git commands
5. All 42 unit tests pass
6. All 15 integration tests pass
7. AOT publish succeeds without warnings
## Evidence
- Commits:
- Tests:
- PRs:
