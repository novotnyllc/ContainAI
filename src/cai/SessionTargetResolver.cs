using System.Text.Json;

namespace ContainAI.Cli.Host;

internal static class SessionTargetResolver
{
    public static async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            if (!string.IsNullOrWhiteSpace(options.Workspace))
            {
                return ResolvedTarget.ErrorResult("--container and --workspace are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--container and --data-volume are mutually exclusive");
            }
        }

        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            if (options.Fresh)
            {
                return ResolvedTarget.ErrorResult("--reset and --fresh are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.Container))
            {
                return ResolvedTarget.ErrorResult("--reset and --container are mutually exclusive");
            }

            if (!string.IsNullOrWhiteSpace(options.DataVolume))
            {
                return ResolvedTarget.ErrorResult("--reset and --data-volume are mutually exclusive");
            }
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            var found = await FindContainerByNameAcrossContextsAsync(
                options.Container,
                options.ExplicitConfig,
                options.Workspace,
                cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(found.Error))
            {
                return ResolvedTarget.ErrorResult(found.Error, found.ErrorCode);
            }

            if (found.Exists)
            {
                var labels = await ReadContainerLabelsAsync(options.Container, found.Context!, cancellationToken).ConfigureAwait(false);
                if (!labels.IsOwned)
                {
                    var code = options.Mode == SessionMode.Run ? 1 : 15;
                    return ResolvedTarget.ErrorResult($"Container '{options.Container}' exists but was not created by ContainAI", code);
                }

                if (string.IsNullOrWhiteSpace(labels.Workspace))
                {
                    return ResolvedTarget.ErrorResult($"Container {options.Container} is missing workspace label");
                }

                if (string.IsNullOrWhiteSpace(labels.DataVolume))
                {
                    return ResolvedTarget.ErrorResult($"Container {options.Container} is missing data-volume label");
                }

                return new ResolvedTarget(
                    ContainerName: options.Container!,
                    Workspace: labels.Workspace!,
                    DataVolume: labels.DataVolume!,
                    Context: found.Context!,
                    ShouldPersistState: true,
                    CreatedByThisInvocation: false,
                    GeneratedFromReset: false,
                    Error: null,
                    ErrorCode: 1);
            }

            var workspaceInput = options.Workspace ?? Directory.GetCurrentDirectory();
            var workspace = SessionRuntimeInfrastructure.NormalizeWorkspacePath(workspaceInput);
            if (!Directory.Exists(workspace))
            {
                return ResolvedTarget.ErrorResult($"Workspace path does not exist: {workspaceInput}");
            }

            var contextSelection = await ResolveContextForWorkspaceAsync(workspace, options.ExplicitConfig, options.Force, cancellationToken).ConfigureAwait(false);
            if (!contextSelection.Success)
            {
                return ResolvedTarget.ErrorResult(contextSelection.Error!, contextSelection.ErrorCode);
            }

            var volume = await ResolveDataVolumeAsync(workspace, options.DataVolume, options.ExplicitConfig, cancellationToken).ConfigureAwait(false);
            if (!volume.Success)
            {
                return ResolvedTarget.ErrorResult(volume.Error!, volume.ErrorCode);
            }

            return new ResolvedTarget(
                ContainerName: options.Container!,
                Workspace: workspace,
                DataVolume: volume.Value!,
                Context: contextSelection.Context!,
                ShouldPersistState: true,
                CreatedByThisInvocation: true,
                GeneratedFromReset: false,
                Error: null,
                ErrorCode: 1);
        }

        var workspacePathInput = options.Workspace ?? Directory.GetCurrentDirectory();
        var normalizedWorkspace = SessionRuntimeInfrastructure.NormalizeWorkspacePath(workspacePathInput);
        if (!Directory.Exists(normalizedWorkspace))
        {
            return ResolvedTarget.ErrorResult($"Workspace path does not exist: {workspacePathInput}");
        }

        var resolvedVolume = await ResolveDataVolumeAsync(normalizedWorkspace, options.DataVolume, options.ExplicitConfig, cancellationToken).ConfigureAwait(false);
        if (!resolvedVolume.Success)
        {
            return ResolvedTarget.ErrorResult(resolvedVolume.Error!, resolvedVolume.ErrorCode);
        }

        var generatedFromReset = false;
        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            resolvedVolume = ResolutionResult<string>.SuccessResult(SessionRuntimeInfrastructure.GenerateWorkspaceVolumeName(normalizedWorkspace));
            generatedFromReset = true;
        }

        var contextResolved = await ResolveContextForWorkspaceAsync(normalizedWorkspace, options.ExplicitConfig, options.Force, cancellationToken).ConfigureAwait(false);
        if (!contextResolved.Success)
        {
            return ResolvedTarget.ErrorResult(contextResolved.Error!, contextResolved.ErrorCode);
        }

        var existing = await FindWorkspaceContainerAsync(normalizedWorkspace, contextResolved.Context!, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(existing.Error))
        {
            return ResolvedTarget.ErrorResult(existing.Error, existing.ErrorCode);
        }

        var containerName = existing.ContainerName;
        var createdByInvocation = false;
        if (string.IsNullOrWhiteSpace(containerName))
        {
            var generated = await ResolveContainerNameForCreationAsync(normalizedWorkspace, contextResolved.Context!, cancellationToken).ConfigureAwait(false);
            if (!generated.Success)
            {
                return ResolvedTarget.ErrorResult(generated.Error!, generated.ErrorCode);
            }

            containerName = generated.Value;
            createdByInvocation = true;
        }

        return new ResolvedTarget(
            ContainerName: containerName!,
            Workspace: normalizedWorkspace,
            DataVolume: resolvedVolume.Value!,
            Context: contextResolved.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: createdByInvocation,
            GeneratedFromReset: generatedFromReset,
            Error: null,
            ErrorCode: 1);
    }

    public static async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            [
                "inspect",
                "--format",
                "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}",
                containerName,
            ],
            cancellationToken).ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return ContainerLabelState.NotFound();
        }

        var parts = inspect.StandardOutput.Trim().Split('|');
        if (parts.Length < 6)
        {
            return ContainerLabelState.NotFound();
        }

        var managed = string.Equals(parts[0], SessionRuntimeConstants.ManagedLabelValue, StringComparison.Ordinal);
        var image = parts[4];
        var owned = managed || SessionRuntimeInfrastructure.IsContainAiImage(image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: SessionRuntimeInfrastructure.NormalizeNoValue(parts[1]),
            DataVolume: SessionRuntimeInfrastructure.NormalizeNoValue(parts[2]),
            SshPort: SessionRuntimeInfrastructure.NormalizeNoValue(parts[3]),
            State: SessionRuntimeInfrastructure.NormalizeNoValue(parts[5]));
    }

    private static async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        var found = new List<string>();
        foreach (var context in contexts)
        {
            var inspect = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "docker",
                ["--context", context, "inspect", "--type", "container", "--", containerName],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                found.Add(context);
            }
        }

        if (found.Count == 0)
        {
            return new FindContainerByNameResult(false, null, null, 1);
        }

        if (found.Count > 1)
        {
            return new FindContainerByNameResult(false, null, $"Container '{containerName}' exists in multiple contexts: {string.Join(", ", found)}", 1);
        }

        return new FindContainerByNameResult(true, found[0], null, 1);
    }

    private static async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (File.Exists(configPath))
        {
            var ws = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
                cancellationToken).ConfigureAwait(false);
            if (ws.ExitCode == 0 && !string.IsNullOrWhiteSpace(ws.StandardOutput))
            {
                using var json = JsonDocument.Parse(ws.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("container_name", out var containerNameElement))
                {
                    var configuredName = containerNameElement.GetString();
                    if (!string.IsNullOrWhiteSpace(configuredName))
                    {
                        var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                            context,
                            ["inspect", "--type", "container", configuredName],
                            cancellationToken).ConfigureAwait(false);
                        if (inspect.ExitCode == 0)
                        {
                            var labels = await ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
                            if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
                            {
                                return ContainerLookupResult.Success(configuredName);
                            }
                        }
                    }
                }
            }
        }

        var byLabel = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return ContainerLookupResult.Empty();
        }

        var ids = byLabel.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (ids.Length > 1)
        {
            return ContainerLookupResult.FromError($"Multiple containers found for workspace: {workspace}");
        }

        if (ids.Length == 1)
        {
            var nameResult = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                context,
                ["inspect", "--format", "{{.Name}}", ids[0]],
                cancellationToken).ConfigureAwait(false);
            if (nameResult.ExitCode == 0)
            {
                return ContainerLookupResult.Success(nameResult.StandardOutput.Trim().TrimStart('/'));
            }
        }

        var generated = await GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", generated],
            cancellationToken).ConfigureAwait(false);
        if (generatedExists.ExitCode == 0)
        {
            return ContainerLookupResult.Success(generated);
        }

        return ContainerLookupResult.Empty();
    }

    private static async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var candidate = baseName;

        for (var suffix = 1; suffix <= 99; suffix++)
        {
            var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                context,
                ["inspect", "--type", "container", candidate],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode != 0)
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
            if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var suffixText = $"-{suffix + 1}";
            var maxBase = Math.Max(1, 24 - suffixText.Length);
            candidate = SessionRuntimeInfrastructure.TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBase)]) + suffixText;
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }

    private static async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var repoName = Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace));
        if (string.IsNullOrWhiteSpace(repoName))
        {
            repoName = "repo";
        }

        var branchName = "nogit";
        var gitProbe = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
            "git",
            ["-C", workspace, "rev-parse", "--is-inside-work-tree"],
            cancellationToken).ConfigureAwait(false);
        if (gitProbe.ExitCode == 0)
        {
            var branch = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "git",
                ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"],
                cancellationToken).ConfigureAwait(false);
            if (branch.ExitCode == 0)
            {
                var value = branch.StandardOutput.Trim();
                branchName = string.IsNullOrWhiteSpace(value) || string.Equals(value, "HEAD", StringComparison.Ordinal) ? "detached" : value;
            }
            else
            {
                branchName = "detached";
            }
        }

        return ContainerNameGenerator.Compose(repoName, branchName);
    }

    private static async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
    {
        var configContext = await ResolveConfiguredContextAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configContext))
        {
            var exists = await SessionRuntimeInfrastructure.DockerContextExistsAsync(configContext, cancellationToken).ConfigureAwait(false);
            if (exists)
            {
                return ContextSelectionResult.FromContext(configContext);
            }
        }

        foreach (var candidate in SessionRuntimeConstants.ContextFallbackOrder)
        {
            if (await SessionRuntimeInfrastructure.DockerContextExistsAsync(candidate, cancellationToken).ConfigureAwait(false))
            {
                return ContextSelectionResult.FromContext(candidate);
            }
        }

        if (force)
        {
            return ContextSelectionResult.FromContext("default");
        }

        return ContextSelectionResult.FromError("No isolation context available. Run 'cai setup' or use --force.");
    }

    private static async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        var configured = await ResolveConfiguredContextAsync(
            workspace ?? Directory.GetCurrentDirectory(),
            explicitConfig,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            contexts.Add(configured);
        }

        foreach (var fallback in SessionRuntimeConstants.ContextFallbackOrder)
        {
            if (!contexts.Contains(fallback, StringComparer.Ordinal) &&
                await SessionRuntimeInfrastructure.DockerContextExistsAsync(fallback, cancellationToken).ConfigureAwait(false))
            {
                contexts.Add(fallback);
            }
        }

        if (!contexts.Contains("default", StringComparer.Ordinal))
        {
            contexts.Add("default");
        }

        return contexts;
    }

    private static async Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var contextResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "secure_engine.context_name"),
            cancellationToken).ConfigureAwait(false);
        if (contextResult.ExitCode != 0)
        {
            return null;
        }

        var context = contextResult.StandardOutput.Trim();
        return string.IsNullOrWhiteSpace(context) ? null : context;
    }

    private static async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            if (!SessionRuntimeInfrastructure.IsValidVolumeName(explicitVolume))
            {
                return ResolutionResult<string>.ErrorResult($"Invalid volume name: {explicitVolume}");
            }

            return ResolutionResult<string>.SuccessResult(explicitVolume);
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            if (!SessionRuntimeInfrastructure.IsValidVolumeName(envVolume))
            {
                return ResolutionResult<string>.ErrorResult($"Invalid volume name in CONTAINAI_DATA_VOLUME: {envVolume}");
            }

            return ResolutionResult<string>.SuccessResult(envVolume);
        }

        var userConfig = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (File.Exists(userConfig))
        {
            var state = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(userConfig, workspace),
                cancellationToken).ConfigureAwait(false);
            if (state.ExitCode == 0 && !string.IsNullOrWhiteSpace(state.StandardOutput))
            {
                using var json = JsonDocument.Parse(state.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("data_volume", out var volumeElement))
                {
                    var value = volumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value))
                    {
                        return ResolutionResult<string>.SuccessResult(value);
                    }
                }
            }
        }

        var discoveredConfig = SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);
        if (!string.IsNullOrWhiteSpace(discoveredConfig) && File.Exists(discoveredConfig))
        {
            var localWorkspace = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(discoveredConfig, workspace),
                cancellationToken).ConfigureAwait(false);
            if (localWorkspace.ExitCode == 0 && !string.IsNullOrWhiteSpace(localWorkspace.StandardOutput))
            {
                using var json = JsonDocument.Parse(localWorkspace.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("data_volume", out var wsVolumeElement))
                {
                    var value = wsVolumeElement.GetString();
                    if (!string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value))
                    {
                        return ResolutionResult<string>.SuccessResult(value);
                    }
                }
            }

            var global = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetKey(discoveredConfig, "agent.data_volume"),
                cancellationToken).ConfigureAwait(false);
            if (global.ExitCode == 0)
            {
                var value = global.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value))
                {
                    return ResolutionResult<string>.SuccessResult(value);
                }
            }
        }

        return ResolutionResult<string>.SuccessResult(SessionRuntimeConstants.DefaultVolume);
    }
}
