namespace ContainAI.Cli.Host;

internal interface ISessionTargetResolutionPipeline
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionTargetResolutionPipeline : ISessionTargetResolutionPipeline
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;
    private readonly ISessionTargetDockerLookupService dockerLookupService;
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;

    public SessionTargetResolutionPipeline()
        : this(
            new SessionTargetParsingValidationService(),
            new SessionTargetDockerLookupService(),
            new SessionTargetWorkspaceDiscoveryService())
    {
    }

    internal SessionTargetResolutionPipeline(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
    {
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
        dockerLookupService = sessionTargetDockerLookupService ?? throw new ArgumentNullException(nameof(sessionTargetDockerLookupService));
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
    }

    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var validationError = parsingValidationService.ValidateOptions(options);
        if (validationError is not null)
        {
            return validationError;
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            return await ResolveExplicitContainerTargetAsync(options, cancellationToken).ConfigureAwait(false);
        }

        return await ResolveWorkspaceTargetAsync(options, cancellationToken).ConfigureAwait(false);
    }

    private async Task<ResolvedTarget> ResolveExplicitContainerTargetAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var found = await dockerLookupService.FindContainerByNameAcrossContextsAsync(
            options.Container!,
            options.ExplicitConfig,
            options.Workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(found.Error))
        {
            return ResolvedTarget.ErrorResult(found.Error, found.ErrorCode);
        }

        if (found.Exists)
        {
            var labels = await dockerLookupService.ReadContainerLabelsAsync(options.Container!, found.Context!, cancellationToken).ConfigureAwait(false);
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

        var workspaceInput = parsingValidationService.ResolveWorkspaceInput(options.Workspace);
        var workspace = parsingValidationService.NormalizeWorkspacePath(workspaceInput);
        if (!workspace.Success)
        {
            return ResolvedTarget.ErrorResult(workspace.Error!, workspace.ErrorCode);
        }

        var contextSelection = await workspaceDiscoveryService.ResolveContextForWorkspaceAsync(
            workspace.Value!,
            options.ExplicitConfig,
            options.Force,
            cancellationToken).ConfigureAwait(false);
        if (!contextSelection.Success)
        {
            return ResolvedTarget.ErrorResult(contextSelection.Error!, contextSelection.ErrorCode);
        }

        var volume = await workspaceDiscoveryService.ResolveDataVolumeAsync(
            workspace.Value!,
            options.DataVolume,
            options.ExplicitConfig,
            cancellationToken).ConfigureAwait(false);
        if (!volume.Success)
        {
            return ResolvedTarget.ErrorResult(volume.Error!, volume.ErrorCode);
        }

        return new ResolvedTarget(
            ContainerName: options.Container!,
            Workspace: workspace.Value!,
            DataVolume: volume.Value!,
            Context: contextSelection.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: true,
            GeneratedFromReset: false,
            Error: null,
            ErrorCode: 1);
    }

    private async Task<ResolvedTarget> ResolveWorkspaceTargetAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var workspacePathInput = parsingValidationService.ResolveWorkspaceInput(options.Workspace);
        var normalizedWorkspace = parsingValidationService.NormalizeWorkspacePath(workspacePathInput);
        if (!normalizedWorkspace.Success)
        {
            return ResolvedTarget.ErrorResult(normalizedWorkspace.Error!, normalizedWorkspace.ErrorCode);
        }

        var resolvedVolume = await workspaceDiscoveryService.ResolveDataVolumeAsync(
            normalizedWorkspace.Value!,
            options.DataVolume,
            options.ExplicitConfig,
            cancellationToken).ConfigureAwait(false);
        if (!resolvedVolume.Success)
        {
            return ResolvedTarget.ErrorResult(resolvedVolume.Error!, resolvedVolume.ErrorCode);
        }

        var generatedFromReset = false;
        if (options.Mode == SessionMode.Shell && options.Reset)
        {
            resolvedVolume = ResolutionResult<string>.SuccessResult(
                SessionRuntimeInfrastructure.GenerateWorkspaceVolumeName(normalizedWorkspace.Value!));
            generatedFromReset = true;
        }

        var contextResolved = await workspaceDiscoveryService.ResolveContextForWorkspaceAsync(
            normalizedWorkspace.Value!,
            options.ExplicitConfig,
            options.Force,
            cancellationToken).ConfigureAwait(false);
        if (!contextResolved.Success)
        {
            return ResolvedTarget.ErrorResult(contextResolved.Error!, contextResolved.ErrorCode);
        }

        var existing = await dockerLookupService.FindWorkspaceContainerAsync(
            normalizedWorkspace.Value!,
            contextResolved.Context!,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(existing.Error))
        {
            return ResolvedTarget.ErrorResult(existing.Error, existing.ErrorCode);
        }

        var containerName = existing.ContainerName;
        var createdByInvocation = false;
        if (string.IsNullOrWhiteSpace(containerName))
        {
            var generated = await dockerLookupService.ResolveContainerNameForCreationAsync(
                normalizedWorkspace.Value!,
                contextResolved.Context!,
                cancellationToken).ConfigureAwait(false);
            if (!generated.Success)
            {
                return ResolvedTarget.ErrorResult(generated.Error!, generated.ErrorCode);
            }

            containerName = generated.Value;
            createdByInvocation = true;
        }

        return new ResolvedTarget(
            ContainerName: containerName!,
            Workspace: normalizedWorkspace.Value!,
            DataVolume: resolvedVolume.Value!,
            Context: contextResolved.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: createdByInvocation,
            GeneratedFromReset: generatedFromReset,
            Error: null,
            ErrorCode: 1);
    }
}
