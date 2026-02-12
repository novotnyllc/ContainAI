using ContainAI.Cli.Host;
using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal interface ISessionWorkspaceConfigReader
{
    Task<string?> TryResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceConfigReader : ISessionWorkspaceConfigReader
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionWorkspaceConfigReader()
        : this(new SessionTargetParsingValidationService(), new SessionRuntimeOperations())
    {
    }

    internal SessionWorkspaceConfigReader(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(sessionTargetParsingValidationService, new SessionRuntimeOperations())
    {
    }

    internal SessionWorkspaceConfigReader(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionRuntimeOperations sessionRuntimeOperations)
    {
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
        runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));
    }

    public async Task<string?> TryResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = runtimeOperations.ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return null;
        }

        var workspaceState = await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceState.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceState.StandardOutput))
        {
            return null;
        }

        return parsingValidationService.TryReadWorkspaceStringProperty(workspaceState.StandardOutput, "container_name");
    }
}
