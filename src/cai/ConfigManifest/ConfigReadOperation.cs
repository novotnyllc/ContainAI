using System.Text.Json;

namespace ContainAI.Cli.Host.ConfigManifest;

internal interface IConfigReadOperation
{
    Task<int> ListAsync(string configPath, CancellationToken cancellationToken);

    Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken);
}

internal sealed class ConfigReadOperation(
    TextWriter standardOutput,
    TextWriter standardError,
    ICaiConfigRuntime runtime) : IConfigReadOperation
{
    public async Task<int> ListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await runtime.RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await standardError.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await standardOutput.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    public async Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key))
        {
            await standardError.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await standardError.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        if (!request.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            var wsResult = await runtime.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspaceScope.Workspace),
                cancellationToken).ConfigureAwait(false);
            if (wsResult.ExitCode != 0)
            {
                return 1;
            }

            using var wsJson = JsonDocument.Parse(wsResult.StandardOutput);
            if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
                wsJson.RootElement.TryGetProperty(request.Key, out var wsValue))
            {
                await standardOutput.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
                return 0;
            }

            return 1;
        }

        var getResult = await runtime.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, normalizedKey),
            cancellationToken).ConfigureAwait(false);

        if (getResult.ExitCode != 0)
        {
            return 1;
        }

        await standardOutput.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }
}
