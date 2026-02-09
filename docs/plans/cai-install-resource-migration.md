# CAI Install + Embedded Resource Migration Plan

## Objective

Move installer/setup behavior from `install.sh` into native `.NET 10` `cai` commands, keep `install.sh` minimal, and embed generation/source assets in the binary via `.resx` + source generator accessors.

## Constraints

- Keep command surface statically modeled with `System.CommandLine`.
- Keep warnings as errors and analyzers active.
- Avoid process-launch wrappers for internal command routing.
- Preserve user-facing behavior parity for installer/setup flows.
- Keep `install.sh` limited to bootstrap duties (download + invoke `cai install`).

## Team Topology (Parallel Work)

- **Orchestrator (main worktree)**:
  - Owns integration, conflict resolution, final verification, and docs.
  - Merges subagent outputs in small commits.
- **Team A (Install Flow)**:
  - Owns `cai install`, typed options, wrapper/path install behavior, and thin `install.sh`.
- **Team B (Embedded Assets + Generator)**:
  - Owns `.resx` content + source generator + runtime asset accessor API.
- **Team C (Command Surface + Examples)**:
  - Owns `examples` command and static command wiring.
- **Review Team**:
  - Parallel review passes for completeness, API consistency, and test depth.

## Implementation Spec

### 1) Native Install Command

- Add a top-level `cai install` command with statically declared options:
  - `--local`
  - `--yes`
  - `--no-setup`
  - `--install-dir <path>`
  - `--bin-dir <path>`
  - `--channel <stable|nightly>` (if download channel is used)
  - `--verbose`
- Model options with strongly typed records in `ContainAI.Cli.Abstractions`.
- Route directly from `System.CommandLine` to typed runtime methods (no argv reparse in runtime).
- Installation behavior in C#:
  - Determine install/bin dirs (flags override env vars, env vars override defaults).
  - Install `cai` binary into install root.
  - Install/update wrapper in bin dir.
  - Emit PATH guidance if needed.
  - Materialize bundled defaults into install/user config dirs from embedded assets.
  - Run setup phase unless `--no-setup`.

### 2) Thin Bootstrap Script

- Keep `install.sh` for:
  - platform detection
  - downloading `cai` binary/bootstrap artifact
  - invoking `cai install` with translated flags
- Remove non-bootstrap install business logic from shell script.

### 3) Embedded Assets via `.resx` + Source Generator

- Add `.resx` containing generation/install seed assets:
  - baseline manifests (`src/manifests/*.toml`)
  - template-system Dockerfile and related defaults needed by generation/setup
  - user-facing example TOML templates
- Add a source generator project that emits strongly typed accessors:
  - constant key names
  - `GetContent(key)` / typed property accessors
  - enumeration APIs by asset category (manifests/templates/examples)
- Runtime uses generated accessor APIs only.

### 4) Examples Command

- Add top-level `cai examples` command:
  - `cai examples list`
  - `cai examples export --output-dir <path> [--force]`
- Export example TOML assets from embedded resources.

### 5) Runtime Integration

- Replace disk-only fallback assumptions for bundled assets with:
  1. install-root files if present
  2. embedded assets fallback
- Ensure manifest generation/check/apply commands can consume embedded defaults when appropriate.

## Testing Strategy

- Unit tests for:
  - command parsing and typed option binding for `install` and `examples`
  - install path resolution precedence (flags/env/defaults)
  - wrapper generation behavior
  - embedded asset accessor coverage (lookup, category filtering, export)
- Integration tests for:
  - `install.sh` -> `cai install` handoff
  - `cai install --local --no-setup` idempotency
  - `cai examples export` file outputs
- Full validation gates:
  - `dotnet build ContainAI.slnx -c Release -warnaserror`
  - `dotnet test --solution ContainAI.slnx -c Release --xunit-info`
  - `dotnet publish src/cai/cai.csproj -c Release -r linux-x64 -warnaserror`

## Documentation Updates

- Update:
  - `docs/quickstart.md`
  - `docs/for-contributors.md`
  - `docs/cli-reference.md`
  - `src/README.md`
  - `AGENTS.md` command snippets
- Document `install.sh` as bootstrap-only and `cai install` as authoritative installer path.

## Completion Criteria

- `install.sh` only bootstraps and delegates to `cai install`.
- `cai install` performs install/setup parity workflows in native code.
- Bundled generation/install/example assets are embedded and accessed via generated strongly typed APIs.
- `cai examples export` emits valid TOML examples.
- Build, test, and publish pass with warnings-as-errors.
