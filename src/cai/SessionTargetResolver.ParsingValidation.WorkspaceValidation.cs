namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetParsingValidationService
{
    public string ResolveWorkspaceInput(string? workspace)
        => workspace ?? Directory.GetCurrentDirectory();

    public ResolutionResult<string> NormalizeWorkspacePath(string workspacePathInput)
    {
        var normalizedWorkspace = SessionRuntimeInfrastructure.NormalizeWorkspacePath(workspacePathInput);
        if (!Directory.Exists(normalizedWorkspace))
        {
            return ResolutionResult<string>.ErrorResult($"Workspace path does not exist: {workspacePathInput}");
        }

        return ResolutionResult<string>.SuccessResult(normalizedWorkspace);
    }

    public ResolutionResult<string> ValidateVolumeName(string volume, string errorPrefix)
        => SessionRuntimeInfrastructure.IsValidVolumeName(volume)
            ? ResolutionResult<string>.SuccessResult(volume)
            : ResolutionResult<string>.ErrorResult($"{errorPrefix}{volume}");
}
