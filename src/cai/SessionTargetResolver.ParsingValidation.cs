namespace ContainAI.Cli.Host;

internal interface ISessionTargetParsingValidationService
{
    ResolvedTarget? ValidateOptions(SessionCommandOptions options);

    string ResolveWorkspaceInput(string? workspace);

    ResolutionResult<string> NormalizeWorkspacePath(string workspacePathInput);

    ResolutionResult<string> ValidateVolumeName(string volume, string errorPrefix);

    string? TryReadWorkspaceStringProperty(string workspaceStateJson, string propertyName);
}

internal sealed partial class SessionTargetParsingValidationService : ISessionTargetParsingValidationService
{
}
