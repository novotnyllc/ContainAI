# fn-44-build-system-net-project-restructuring.3 Refactor ACP code into ContainAI.Acp library and acp-proxy CLI

## Description
Refactor the monolithic Program.cs (1029 lines) into a proper library/CLI structure with ContainAI.Acp library and acp-proxy CLI application. Use StreamJsonRpc for JSON-RPC protocol, CliWrap for process management. Add xUnit 3 unit tests.

**Size:** M
**Files:**
- `src/ContainAI.Acp/ContainAI.Acp.csproj` (new library)
- `src/ContainAI.Acp/Protocol/` (new - StreamJsonRpc integration)
- `src/ContainAI.Acp/Sessions/` (new - session management with CliWrap)
- `src/ContainAI.Acp/PathTranslation/` (new - path translation)
- `src/acp-proxy/acp-proxy.csproj` (update - reference library)
- `src/acp-proxy/Program.cs` (simplify to CLI entry point)
- `tests/ContainAI.Acp.Tests/ContainAI.Acp.Tests.csproj` (new - xUnit 3 tests)
- `tests/ContainAI.Acp.Tests/*.cs` (new - test files)
- `ContainAI.slnx` (add new projects)

## Approach

1. **Create ContainAI.Acp library project** with proper structure:
   - `Protocol/` - Use StreamJsonRpc for JSON-RPC message handling
   - `Sessions/` - Session management using CliWrap for process spawning
   - `PathTranslation/` - Host/container path mapping
   - Keep AOT-compatible

2. **Use StreamJsonRpc for JSON-RPC**:
   - Microsoft's production JSON-RPC implementation
   - Handles message framing, serialization, request/response correlation
   - Supports NDJSON (newline-delimited) format
   - Properly handles bidirectional communication

3. **Use CliWrap for process execution**:
   - Fluent API for spawning MCP server processes
   - Clean stdin/stdout piping
   - Proper cancellation support

4. **Update acp-proxy CLI** to be thin wrapper:
   - Parse command line arguments
   - Initialize and run the ACP server from library
   - Handle process lifecycle

5. **Create xUnit 3 test project**:
   - Test protocol handling with StreamJsonRpc
   - Test path translation logic
   - Test session state management
   - Use `[Fact]` and `[Theory]` attributes

## Key context

- StreamJsonRpc handles JSON-RPC 2.0 protocol correctly
- Current code has manual JSON-RPC handling that StreamJsonRpc replaces
- Session management handles multiple concurrent MCP sessions
- Path translation maps between host and container paths
- Race condition pitfall: StreamJsonRpc handles request/response correlation properly
- CliWrap is AOT-compatible
## Approach

1. **Create ContainAI.Acp library project** with proper structure:
   - `Protocol/` - JSON-RPC message types, serialization
   - `Sessions/` - Session management using CliWrap for process spawning
   - `PathTranslation/` - Host/container path mapping
   - Keep AOT-compatible (no reflection)

2. **Replace ProcessStartInfo with CliWrap**:
   - Use `Cli.Wrap()` fluent API for spawning MCP server processes
   - Use `PipeTarget` for stdout/stderr handling
   - Use `CancellationToken` for process cancellation
   - CliWrap handles stdin/stdout piping cleanly

3. **Update acp-proxy CLI** to be thin wrapper:
   - Parse command line arguments
   - Initialize and run the ACP server from library
   - Handle process lifecycle

4. **Create xUnit 3 test project**:
   - Add `tests/ContainAI.Acp.Tests/ContainAI.Acp.Tests.csproj`
   - Use xUnit 3.x (latest) with `Microsoft.NET.Test.Sdk`
   - Test protocol serialization/deserialization
   - Test path translation logic
   - Test session state management
   - Use `[Fact]` and `[Theory]` attributes

5. **Preserve AOT compatibility**: Use `[JsonSerializable]` attributes, avoid reflection. CliWrap is AOT-compatible.

## Key context

- Current code uses System.Text.Json source generators for AOT
- Session management handles multiple concurrent MCP sessions
- Path translation maps between host and container paths
- NDJSON framing for message protocol (per `.flow/memory/conventions.md`)
- Race condition pitfall: Register TCS before sending request (per `.flow/memory/pitfalls.md:381`)
- CliWrap: https://github.com/Tyrrrz/CliWrap - fluent process execution library
- CliWrap is AOT-compatible and has no reflection usage
## Approach

1. **Create ContainAI.Acp library project** with proper structure:
   - `Protocol/` - JSON-RPC message types, serialization
   - `Sessions/` - Session management, process spawning
   - `PathTranslation/` - Host/container path mapping
   - Keep AOT-compatible (no reflection)

2. **Update acp-proxy CLI** to be thin wrapper:
   - Parse command line arguments
   - Initialize and run the ACP server from library
   - Handle process lifecycle

3. **Create xUnit 3 test project**:
   - Add `tests/ContainAI.Acp.Tests/ContainAI.Acp.Tests.csproj`
   - Use xUnit 3.x (latest) with `Microsoft.NET.Test.Sdk`
   - Test protocol serialization/deserialization
   - Test path translation logic
   - Test session state management
   - Use `[Fact]` and `[Theory]` attributes

4. **Preserve AOT compatibility**: Use `[JsonSerializable]` attributes, avoid reflection.

## Key context

- Current code uses System.Text.Json source generators for AOT
- Session management handles multiple concurrent MCP sessions
- Path translation maps between host and container paths
- NDJSON framing for message protocol (per `.flow/memory/conventions.md`)
- Race condition pitfall: Register TCS before sending request (per `.flow/memory/pitfalls.md:381`)
- xUnit 3 supports parallel test execution and modern .NET features
## Approach

1. **Create ContainAI.Acp library project** with proper structure:
   - `Protocol/` - JSON-RPC message types, serialization
   - `Sessions/` - Session management, process spawning
   - `PathTranslation/` - Host/container path mapping
   - Keep AOT-compatible (no reflection)

2. **Update acp-proxy CLI** to be thin wrapper:
   - Parse command line arguments
   - Initialize and run the ACP server from library
   - Handle process lifecycle

3. **Preserve AOT compatibility**: Use `[JsonSerializable]` attributes, avoid reflection.

## Key context

- Current code uses System.Text.Json source generators for AOT
- Session management handles multiple concurrent MCP sessions
- Path translation maps between host and container paths
- NDJSON framing for message protocol (per `.flow/memory/conventions.md`)
- Race condition pitfall: Register TCS before sending request (per `.flow/memory/pitfalls.md:381`)
## Acceptance
- [ ] ContainAI.Acp library project exists and builds
- [ ] Library uses StreamJsonRpc for JSON-RPC protocol
- [ ] Library uses CliWrap for all process execution (no raw ProcessStartInfo)
- [ ] Library is AOT-compatible (no trimming warnings)
- [ ] acp-proxy CLI references ContainAI.Acp library
- [ ] acp-proxy CLI builds as self-contained AOT binary
- [ ] xUnit 3 test project exists at tests/ContainAI.Acp.Tests/
- [ ] Unit tests cover JSON-RPC message handling
- [ ] Unit tests cover path translation
- [ ] Unit tests cover session management
- [ ] `dotnet test` passes all unit tests
- [ ] All existing ACP functionality preserved
- [ ] `tests/integration/test-acp-proxy.sh` passes
- [ ] Library can be referenced by external projects (future NuGet publishing)
- [ ] Code follows project conventions (no single 1000+ line files)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
