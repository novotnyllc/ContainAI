namespace ContainAI.Cli.Host;

internal interface ISessionTargetConfiguredContextResolver
{
    Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetConfiguredContextResolver : ISessionTargetConfiguredContextResolver
{
    public async Task<string?> ResolveConfiguredContextAsync(string workspace, string? explicitConfig, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var contextResult = await SessionRuntimeInfrastructure.RunTomlAsync(
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
