# fn-44-build-system-net-project-restructuring.2 Set up .NET project infrastructure (CPM, NBGV, ArtifactsOutput, slnx)

## Description
Set up modern .NET project infrastructure with Central Package Management, NBGV versioning (for ALL build versions, not just .NET), ArtifactsOutput, and slnx solution format.

**Size:** M
**Files:**
- `Directory.Build.props` (new)
- `Directory.Packages.props` (new)
- `version.json` (new)
- `ContainAI.slnx` (new, replaces `ContainAI.sln`)
- `src/acp-proxy/acp-proxy.csproj` (update)
- `nuget.config` (new or update)
- `.github/workflows/docker.yml` (add NBGV action)

## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables (`NBGV_SemVer2`, `NBGV_SimpleVersion`, `NBGV_GitCommitId`, etc.) that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions including:
   - `Nerdbank.GitVersioning` (GlobalPackageReference)
   - `Microsoft.SourceLink.GitHub`
   - `StreamJsonRpc` - JSON-RPC protocol handling
   - `CliWrap` - Process execution
   - `xunit.v3` - Testing (VSTest v2 native)
   - `Microsoft.NET.Test.Sdk`

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **GitHub Actions NBGV setup**:
   ```yaml
   - uses: dotnet/nbgv@master
     id: nbgv
   # All subsequent steps can use ${{ steps.nbgv.outputs.SemVer2 }}
   # Or env: NBGV_SemVer2, NBGV_SimpleVersion, etc.
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- NBGV outputs are available as both step outputs AND environment variables
- Shell scripts in CI can use `$NBGV_SemVer2` directly after the NBGV action runs
- Docker build can use `--build-arg VERSION=$NBGV_SemVer2`
- StreamJsonRpc is Microsoft's production JSON-RPC implementation
- xUnit 3 uses VSTest v2 natively - no separate runner needed
- CliWrap provides fluent API for process execution
## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables (`NBGV_SemVer2`, `NBGV_SimpleVersion`, `NBGV_GitCommitId`, etc.) that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions including:
   - `Nerdbank.GitVersioning` (GlobalPackageReference)
   - `Microsoft.SourceLink.GitHub`
   - `CliWrap` (process management, replaces ProcessStartInfo)
   - `xunit.v3` (xUnit 3 with VSTest v2 integration - no separate runner needed)
   - `Microsoft.NET.Test.Sdk`

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **GitHub Actions NBGV setup**:
   ```yaml
   - uses: dotnet/nbgv@master
     id: nbgv
   # All subsequent steps can use ${{ steps.nbgv.outputs.SemVer2 }}
   # Or env: NBGV_SemVer2, NBGV_SimpleVersion, etc.
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- NBGV outputs are available as both step outputs AND environment variables
- Shell scripts in CI can use `$NBGV_SemVer2` directly after the NBGV action runs
- Docker build can use `--build-arg VERSION=$NBGV_SemVer2`
- xUnit 3 uses VSTest v2 natively - no `xunit.runner.visualstudio` package needed
- CliWrap provides fluent API for process execution, better than raw ProcessStartInfo
## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables (`NBGV_SemVer2`, `NBGV_SimpleVersion`, `NBGV_GitCommitId`, etc.) that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions including:
   - `Nerdbank.GitVersioning` (GlobalPackageReference)
   - `Microsoft.SourceLink.GitHub`
   - `CliWrap` (process management, replaces ProcessStartInfo)
   - `xunit` (3.x)
   - `xunit.runner.visualstudio`
   - `Microsoft.NET.Test.Sdk`

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **GitHub Actions NBGV setup**:
   ```yaml
   - uses: dotnet/nbgv@master
     id: nbgv
   # All subsequent steps can use ${{ steps.nbgv.outputs.SemVer2 }}
   # Or env: NBGV_SemVer2, NBGV_SimpleVersion, etc.
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- NBGV outputs are available as both step outputs AND environment variables
- Shell scripts in CI can use `$NBGV_SemVer2` directly after the NBGV action runs
- Docker build can use `--build-arg VERSION=$NBGV_SemVer2`
- xUnit 3 is the latest major version with improved performance and features
- CliWrap provides fluent API for process execution, better than raw ProcessStartInfo
## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables (`NBGV_SemVer2`, `NBGV_SimpleVersion`, `NBGV_GitCommitId`, etc.) that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions including:
   - `Nerdbank.GitVersioning` (GlobalPackageReference)
   - `Microsoft.SourceLink.GitHub`
   - `xunit` (3.x)
   - `xunit.runner.visualstudio`
   - `Microsoft.NET.Test.Sdk`

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **GitHub Actions NBGV setup**:
   ```yaml
   - uses: dotnet/nbgv@master
     id: nbgv
   # All subsequent steps can use ${{ steps.nbgv.outputs.SemVer2 }}
   # Or env: NBGV_SemVer2, NBGV_SimpleVersion, etc.
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- NBGV outputs are available as both step outputs AND environment variables
- Shell scripts in CI can use `$NBGV_SemVer2` directly after the NBGV action runs
- Docker build can use `--build-arg VERSION=$NBGV_SemVer2`
- xUnit 3 is the latest major version with improved performance and features
## Approach

1. **NBGV for unified versioning**: NBGV sets environment variables (`NBGV_SemVer2`, `NBGV_SimpleVersion`, `NBGV_GitCommitId`, etc.) that ALL build steps can use - shell scripts, Docker builds, release tags, etc.

2. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions.

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`.

5. **GitHub Actions NBGV setup**:
   ```yaml
   - uses: dotnet/nbgv@master
     id: nbgv
   # All subsequent steps can use ${{ steps.nbgv.outputs.SemVer2 }}
   # Or env: NBGV_SemVer2, NBGV_SimpleVersion, etc.
   ```

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- NBGV outputs are available as both step outputs AND environment variables
- Shell scripts in CI can use `$NBGV_SemVer2` directly after the NBGV action runs
- Docker build can use `--build-arg VERSION=$NBGV_SemVer2`
## Approach

1. **Central Package Management**: Create `Directory.Packages.props` at repo root with all package versions. Update csproj to remove version attributes from PackageReference items.

2. **NBGV**: Create `version.json` with initial version `0.1` and configure `publicReleaseRefSpec` for main branch. Add NBGV as GlobalPackageReference.

3. **ArtifactsOutput**: Add `UseArtifactsOutput` to `Directory.Build.props`. Output goes to `artifacts/` directory.

4. **slnx migration**: Run `dotnet sln migrate` to convert `ContainAI.sln` to `ContainAI.slnx`. Delete old .sln file.

5. **SourceLink**: Add Microsoft.SourceLink.GitHub for debugging support.

## Key context

- NBGV requires `fetch-depth: 0` in GitHub Actions checkout (critical!)
- CPM with `CentralPackageTransitivePinningEnabled` for transitive control
- ArtifactsOutput structure: `artifacts/bin/<project>/<config>/`, `artifacts/publish/<project>/<config>/`
- Current packages in acp-proxy.csproj: no external packages (all BCL)
## Acceptance
- [ ] `Directory.Build.props` exists with ArtifactsOutput enabled
- [ ] `Directory.Packages.props` exists with CPM enabled
- [ ] `Directory.Packages.props` includes StreamJsonRpc package
- [ ] `Directory.Packages.props` includes CliWrap package
- [ ] `Directory.Packages.props` includes xunit.v3 (no separate runner package)
- [ ] `version.json` exists with NBGV configuration
- [ ] `ContainAI.slnx` exists and builds successfully
- [ ] Old `ContainAI.sln` removed
- [ ] `dotnet build` produces output in `artifacts/bin/`
- [ ] `nbgv get-version` returns valid version
- [ ] GitHub Actions workflow uses NBGV action with fetch-depth: 0
- [ ] NBGV env vars available to all subsequent CI steps (not just .NET)
- [ ] Docker build uses NBGV version for OCI labels
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
