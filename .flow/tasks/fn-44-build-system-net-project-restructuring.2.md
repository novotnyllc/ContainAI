# fn-44-build-system-net-project-restructuring.2 Set up .NET project infrastructure (CPM, NBGV, ArtifactsOutput, slnx)

## Description
Set up modern .NET project infrastructure with Central Package Management, NBGV versioning (for ALL build versions, not just .NET), ArtifactsOutput, and slnx solution format.

**Size:** M
**Files:**
- `Directory.Build.props` (new)
- `Directory.Packages.props` (new)
- `version.json` (new)
- `global.json` (new - SDK version + MTP test runner config)
- `.config/dotnet-tools.json` (new - local tool manifest with nbgv)
- `ContainAI.slnx` (new, replaces `ContainAI.sln`)
- `src/acp-proxy/acp-proxy.csproj` (update)
- `nuget.config` (new or update)
- `.github/workflows/docker.yml` (update for NBGV as .NET tool)

## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions including:
   - `Nerdbank.GitVersioning` (GlobalPackageReference)
   - `Microsoft.SourceLink.GitHub`
   - `System.CommandLine` - CLI parsing (AOT-compatible)
   - `StreamJsonRpc` - JSON-RPC implementation (AOT-compatible with SystemTextJsonFormatter)
   - `CliWrap` - Process execution (AOT-compatible)
   - `xunit.v3` - Testing framework (no runner packages needed with .NET 10 MTP)

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **NBGV as .NET local tool** (not GitHub Action):
   - Create `.config/dotnet-tools.json` manifest with nbgv tool (no pinned version)
   - Use `dotnet tool restore` to install
   - Use `dotnet nbgv get-version -v <variable>` to get version info

6. **version.json with release branching**:
   - Main branch: `"version": "0.2-dev"` (prerelease suffix)
   - Release branches (`rel/v0.2`): `"version": "0.2"` (stable)
   - NBGV derives full SemVer from branch + git height

7. **GitHub Actions setup** (use setup-dotnet with global.json):
   ```yaml
   - uses: actions/checkout@v4
     with:
       fetch-depth: 0  # CRITICAL for NBGV
   - uses: actions/setup-dotnet@v4
     with:
       global-json-file: global.json  # Use SDK version from global.json
   - name: Install and run NBGV
     run: |
       dotnet tool restore
       echo "NBGV_SemVer2=$(dotnet nbgv get-version -v SemVer2)" >> "$GITHUB_ENV"
       echo "NBGV_SimpleVersion=$(dotnet nbgv get-version -v SimpleVersion)" >> "$GITHUB_ENV"
       echo "NBGV_GitCommitId=$(dotnet nbgv get-version -v GitCommitId)" >> "$GITHUB_ENV"
   ```

8. **global.json for .NET 10 MTP**: Configure Microsoft Testing Platform as test runner:
   ```json
   {
     "sdk": { "version": "10.0.100" },
     "test": { "runner": "Microsoft.Testing.Platform" }
   }
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- Use NBGV as .NET local tool (not GitHub Action) for better reproducibility
- `setup-dotnet` action must use `global-json-file: global.json` to get correct SDK version
- `dotnet tool restore` installs tools from `.config/dotnet-tools.json`
- `dotnet nbgv get-version -v <var>` outputs specific version components
- System.CommandLine is AOT-compatible (used by .NET CLI itself)
- StreamJsonRpc is AOT-compatible with SystemTextJsonFormatter (not Newtonsoft)
- CliWrap provides fluent API for process execution, is AOT-compatible
- .NET 10 TestPlatform v2 (MTP) eliminates need for `xunit.runner.visualstudio` and `Microsoft.NET.Test.Sdk`

## Acceptance
- [ ] `Directory.Build.props` exists with ArtifactsOutput enabled
- [ ] `Directory.Packages.props` exists with CPM enabled
- [ ] `Directory.Packages.props` includes System.CommandLine package
- [ ] `Directory.Packages.props` includes StreamJsonRpc package
- [ ] `Directory.Packages.props` includes CliWrap package
- [ ] `Directory.Packages.props` includes xunit.v3 (no runner packages needed with MTP)
- [ ] `Directory.Packages.props` does NOT include xunit.runner.visualstudio (not needed)
- [ ] `Directory.Packages.props` does NOT include Microsoft.NET.Test.Sdk (not needed)
- [ ] `global.json` configures `"test": { "runner": "Microsoft.Testing.Platform" }`
- [ ] `version.json` exists with `-dev` prerelease suffix on main
- [ ] `version.json` has NBGV configuration for `rel/v*` release branches
- [ ] `ContainAI.slnx` exists and builds successfully
- [ ] Old `ContainAI.sln` removed
- [ ] `dotnet build` produces output in `artifacts/bin/`
- [ ] `dotnet test` works with MTP runner (no VSTest)
- [ ] `.config/dotnet-tools.json` manifest exists with nbgv tool (no pinned version)
- [ ] `dotnet tool restore && dotnet nbgv get-version` returns valid version
- [ ] GitHub Actions uses `setup-dotnet` with `global-json-file: global.json`
- [ ] Checkout uses `fetch-depth: 0`
- [ ] NBGV env vars exported via `dotnet nbgv get-version -v <var>`
- [ ] Shell steps can access `$NBGV_SemVer2` after export
- [ ] Docker build uses NBGV version for OCI labels

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
