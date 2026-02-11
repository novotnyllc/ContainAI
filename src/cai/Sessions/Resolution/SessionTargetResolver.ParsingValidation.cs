using System.Text.Json;

namespace ContainAI.Cli.Host;

internal interface ISessionTargetParsingValidationService
{
    ResolvedTarget? ValidateOptions(SessionCommandOptions options);

    string ResolveWorkspaceInput(string? workspace);

    ResolutionResult<string> NormalizeWorkspacePath(string workspacePathInput);

    ResolutionResult<string> ValidateVolumeName(string volume, string errorPrefix);

    string? TryReadWorkspaceStringProperty(string workspaceStateJson, string propertyName);
}

internal sealed class SessionTargetParsingValidationService : ISessionTargetParsingValidationService
{
    public ResolvedTarget? ValidateOptions(SessionCommandOptions options)
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

        return null;
    }

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

    public string? TryReadWorkspaceStringProperty(string workspaceStateJson, string propertyName)
    {
        using var json = JsonDocument.Parse(workspaceStateJson);
        if (json.RootElement.ValueKind != JsonValueKind.Object ||
            !json.RootElement.TryGetProperty(propertyName, out var propertyValue))
        {
            return null;
        }

        var value = propertyValue.GetString();
        return string.IsNullOrWhiteSpace(value) ? null : value;
    }
}
