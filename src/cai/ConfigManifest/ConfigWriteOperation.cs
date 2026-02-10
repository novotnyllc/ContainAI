namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigWriteOperation
{
    Task<int> SetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);

    Task<int> UnsetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}

internal sealed class ConfigWriteOperation(
    TextWriter standardError,
    ICaiConfigRuntime runtime) : IConfigWriteOperation
{
    public async Task<int> SetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key) || request.Value is null)
        {
            await standardError.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await standardError.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        TomlProcessResult setResult;
        if (!request.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            setResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.SetWorkspaceKey(configPath, workspaceScope.Workspace, request.Key, request.Value),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            setResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.SetKey(configPath, normalizedKey, request.Value),
                cancellationToken).ConfigureAwait(false);
        }

        if (setResult.ExitCode != 0)
        {
            await standardError.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    public async Task<int> UnsetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key))
        {
            await standardError.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await standardError.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        TomlProcessResult unsetResult;
        if (!request.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            unsetResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.UnsetWorkspaceKey(configPath, workspaceScope.Workspace, request.Key),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            unsetResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.UnsetKey(configPath, normalizedKey),
                cancellationToken).ConfigureAwait(false);
        }

        if (unsetResult.ExitCode != 0)
        {
            await standardError.WriteLineAsync(unsetResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
