namespace ContainAI.Cli.Host;

internal interface ISessionTargetWorkspacePathOptionResolver
{
    ResolutionResult<string> ResolveWorkspace(SessionCommandOptions options);
}

internal sealed class SessionTargetWorkspacePathOptionResolver : ISessionTargetWorkspacePathOptionResolver
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    internal SessionTargetWorkspacePathOptionResolver(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        => parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));

    public ResolutionResult<string> ResolveWorkspace(SessionCommandOptions options)
    {
        var workspaceInput = parsingValidationService.ResolveWorkspaceInput(options.Workspace);
        var normalized = parsingValidationService.NormalizeWorkspacePath(workspaceInput);
        if (!normalized.Success)
        {
            return ResolutionResult<string>.ErrorResult(normalized.Error!, normalized.ErrorCode);
        }

        return ResolutionResult<string>.SuccessResult(normalized.Value!);
    }
}
