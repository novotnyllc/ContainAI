using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

internal interface ISessionTargetWorkspacePathOptionResolver
{
    ResolutionResult<string> ResolveWorkspace(SessionCommandOptions options);
}
