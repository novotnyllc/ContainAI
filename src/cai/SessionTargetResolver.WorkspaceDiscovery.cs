namespace ContainAI.Cli.Host;

internal static class SessionTargetWorkspaceDiscoveryService
{
    public static async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
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

    public static async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
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

    public static async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return SessionTargetParsingValidationService.ValidateVolumeName(explicitVolume, "Invalid volume name: ");
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            return SessionTargetParsingValidationService.ValidateVolumeName(envVolume, "Invalid volume name in CONTAINAI_DATA_VOLUME: ");
        }

        var userConfig = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (File.Exists(userConfig))
        {
            var state = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(userConfig, workspace),
                cancellationToken).ConfigureAwait(false);
            if (state.ExitCode == 0 && !string.IsNullOrWhiteSpace(state.StandardOutput))
            {
                var value = SessionTargetParsingValidationService.TryReadWorkspaceStringProperty(state.StandardOutput, "data_volume");
                if (!string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value))
                {
                    return ResolutionResult<string>.SuccessResult(value);
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
                var value = SessionTargetParsingValidationService.TryReadWorkspaceStringProperty(localWorkspace.StandardOutput, "data_volume");
                if (!string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value))
                {
                    return ResolutionResult<string>.SuccessResult(value);
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

    public static async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
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
}
