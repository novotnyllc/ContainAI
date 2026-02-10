namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed partial class ConfigWriteOperation
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
}
