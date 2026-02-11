namespace ContainAI.Cli.Host;

internal interface ISessionWorkspaceConfigReader
{
    Task<string?> TryResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceConfigReader : ISessionWorkspaceConfigReader
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    public SessionWorkspaceConfigReader()
        : this(new SessionTargetParsingValidationService())
    {
    }

    internal SessionWorkspaceConfigReader(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        => parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));

    public async Task<string?> TryResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return null;
        }

        var workspaceState = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceState.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceState.StandardOutput))
        {
            return null;
        }

        return parsingValidationService.TryReadWorkspaceStringProperty(workspaceState.StandardOutput, "container_name");
    }
}
