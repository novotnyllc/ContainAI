namespace ContainAI.Cli.Host;

internal interface ISessionTargetWorkspaceDiscoveryService
{
    Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken);

    Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken);

    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);

    Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken);
}

internal sealed class SessionTargetWorkspaceDiscoveryService : ISessionTargetWorkspaceDiscoveryService
{
    private readonly ISessionTargetContextDiscoveryService contextDiscoveryService;
    private readonly ISessionTargetDataVolumeResolutionService dataVolumeResolutionService;
    private readonly ISessionTargetContainerNameGenerationService containerNameGenerationService;

    public SessionTargetWorkspaceDiscoveryService()
        : this(new SessionTargetParsingValidationService())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(
            new SessionTargetContextDiscoveryService(new SessionTargetConfiguredContextResolver()),
            new SessionTargetDataVolumeResolutionService(sessionTargetParsingValidationService),
            new SessionTargetContainerNameGenerationService())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(
        ISessionTargetContextDiscoveryService sessionTargetContextDiscoveryService,
        ISessionTargetDataVolumeResolutionService sessionTargetDataVolumeResolutionService,
        ISessionTargetContainerNameGenerationService sessionTargetContainerNameGenerationService)
    {
        contextDiscoveryService = sessionTargetContextDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetContextDiscoveryService));
        dataVolumeResolutionService = sessionTargetDataVolumeResolutionService ?? throw new ArgumentNullException(nameof(sessionTargetDataVolumeResolutionService));
        containerNameGenerationService = sessionTargetContainerNameGenerationService ?? throw new ArgumentNullException(nameof(sessionTargetContainerNameGenerationService));
    }

    public async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
        => await contextDiscoveryService.ResolveContextForWorkspaceAsync(workspace, explicitConfig, force, cancellationToken).ConfigureAwait(false);

    public async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
        => await contextDiscoveryService.BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);

    public async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
        => await dataVolumeResolutionService.ResolveDataVolumeAsync(workspace, explicitVolume, explicitConfig, cancellationToken).ConfigureAwait(false);

    public async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
        => await containerNameGenerationService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
}

internal interface ISessionTargetContextDiscoveryService
{
    Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken);

    Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal interface ISessionTargetConfiguredContextResolver
{
    Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal interface ISessionTargetDataVolumeResolutionService
{
    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);
}

internal interface ISessionTargetContainerNameGenerationService
{
    Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken);
}

internal sealed class SessionTargetContextDiscoveryService : ISessionTargetContextDiscoveryService
{
    private const string DefaultContextName = "default";
    private readonly ISessionTargetConfiguredContextResolver configuredContextResolver;

    internal SessionTargetContextDiscoveryService(ISessionTargetConfiguredContextResolver sessionTargetConfiguredContextResolver)
        => configuredContextResolver = sessionTargetConfiguredContextResolver ?? throw new ArgumentNullException(nameof(sessionTargetConfiguredContextResolver));

    public async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
    {
        var configured = await configuredContextResolver.ResolveConfiguredContextAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configured) &&
            await SessionRuntimeInfrastructure.DockerContextExistsAsync(configured, cancellationToken).ConfigureAwait(false))
        {
            return ContextSelectionResult.FromContext(configured);
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
            return ContextSelectionResult.FromContext(DefaultContextName);
        }

        return ContextSelectionResult.FromError("No isolation context available. Run 'cai setup' or use --force.");
    }

    public async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var contexts = new List<string>();
        var configured = await configuredContextResolver.ResolveConfiguredContextAsync(
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

        if (!contexts.Contains(DefaultContextName, StringComparer.Ordinal))
        {
            contexts.Add(DefaultContextName);
        }

        return contexts;
    }
}

internal sealed class SessionTargetConfiguredContextResolver : ISessionTargetConfiguredContextResolver
{
    public async Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken)
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
}

internal sealed class SessionTargetDataVolumeResolutionService : ISessionTargetDataVolumeResolutionService
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    internal SessionTargetDataVolumeResolutionService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        => parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));

    public async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return parsingValidationService.ValidateVolumeName(explicitVolume, "Invalid volume name: ");
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            return parsingValidationService.ValidateVolumeName(envVolume, "Invalid volume name in CONTAINAI_DATA_VOLUME: ");
        }

        var userConfigVolume = await TryResolveWorkspaceVolumeAsync(
            SessionRuntimeInfrastructure.ResolveUserConfigPath(),
            workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(userConfigVolume))
        {
            return ResolutionResult<string>.SuccessResult(userConfigVolume);
        }

        var discoveredConfig = SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);
        var workspaceVolume = await TryResolveWorkspaceVolumeAsync(discoveredConfig, workspace, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(workspaceVolume))
        {
            return ResolutionResult<string>.SuccessResult(workspaceVolume);
        }

        var globalVolume = await TryResolveGlobalVolumeAsync(discoveredConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(globalVolume))
        {
            return ResolutionResult<string>.SuccessResult(globalVolume);
        }

        return ResolutionResult<string>.SuccessResult(SessionRuntimeConstants.DefaultVolume);
    }

    private async Task<string?> TryResolveWorkspaceVolumeAsync(string? configPath, string workspace, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var workspaceResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceResult.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
        {
            return null;
        }

        var value = parsingValidationService.TryReadWorkspaceStringProperty(workspaceResult.StandardOutput, "data_volume");
        return IsValidVolume(value) ? value : null;
    }

    private static async Task<string?> TryResolveGlobalVolumeAsync(string? configPath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var globalResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);
        if (globalResult.ExitCode != 0)
        {
            return null;
        }

        var value = globalResult.StandardOutput.Trim();
        return IsValidVolume(value) ? value : null;
    }

    private static bool IsValidVolume(string? value)
        => !string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value);
}

internal sealed class SessionTargetContainerNameGenerationService : ISessionTargetContainerNameGenerationService
{
    public async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
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
