using System.Text.Json;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Validation;

internal interface ISessionTargetParsingValidationService
{
    ResolvedTarget? ValidateOptions(SessionCommandOptions options);

    string ResolveWorkspaceInput(string? workspace);

    ResolutionResult<string> NormalizeWorkspacePath(string workspacePathInput);

    ResolutionResult<string> ValidateVolumeName(string volume, string errorPrefix);

    string? TryReadWorkspaceStringProperty(string workspaceStateJson, string propertyName);
}
