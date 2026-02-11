namespace ContainAI.Cli.Host;

internal interface ISessionTargetConfiguredContextResolver
{
    Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetConfiguredContextResolver : ISessionTargetConfiguredContextResolver
{
    private readonly ISessionRuntimeOperations runtimeOperations;

    public SessionTargetConfiguredContextResolver()
        : this(new SessionRuntimeOperations())
    {
    }

    internal SessionTargetConfiguredContextResolver(ISessionRuntimeOperations sessionRuntimeOperations)
        => runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));

    public async Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var configPath = runtimeOperations.FindConfigFile(workspace, explicitConfig);
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var contextResult = await runtimeOperations.RunTomlAsync(
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
