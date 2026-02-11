using System.Text.Json;
using ContainAI.Cli.Host.ConfigManifest;

namespace ContainAI.Cli.Host.ConfigManifest.Reading;

internal sealed class ConfigValueReader(ICaiConfigRuntime runtime)
{
    public Task<TomlProcessResult> ReadConfigJsonAsync(string configPath, CancellationToken cancellationToken) =>
        runtime.RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken);

    public Task<TomlProcessResult> ReadConfigKeyAsync(string configPath, string key, CancellationToken cancellationToken) =>
        runtime.RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, key), cancellationToken);

    public async Task<WorkspaceReadResult> ReadWorkspaceValueAsync(
        string configPath,
        string workspace,
        string requestKey,
        CancellationToken cancellationToken)
    {
        var workspaceResult = await runtime.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);

        if (workspaceResult.ExitCode != 0)
        {
            return WorkspaceReadResult.ExecutionError;
        }

        using var wsJson = JsonDocument.Parse(workspaceResult.StandardOutput);
        if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
            wsJson.RootElement.TryGetProperty(requestKey, out var workspaceValue))
        {
            return WorkspaceReadResult.Found(workspaceValue.ToString());
        }

        return WorkspaceReadResult.Missing;
    }
}
