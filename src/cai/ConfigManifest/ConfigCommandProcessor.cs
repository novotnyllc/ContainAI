using System.Text.Json;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ConfigCommandProcessor : IConfigCommandProcessor
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly ICaiConfigRuntime runtime;

    public ConfigCommandProcessor(TextWriter standardOutput, TextWriter standardError, ICaiConfigRuntime runtime)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
    }

    public async Task<int> RunAsync(ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.Equals(request.Action, "resolve-volume", StringComparison.Ordinal))
        {
            return await ResolveVolumeAsync(request, cancellationToken).ConfigureAwait(false);
        }

        var configPath = runtime.ResolveConfigPath(request.Workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        return request.Action switch
        {
            "list" => await ListAsync(configPath, cancellationToken).ConfigureAwait(false),
            "get" => await GetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            "set" => await SetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            "unset" => await UnsetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }

    private async Task<int> ListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await runtime.RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> GetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key))
        {
            await stderr.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
                await stdout.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
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

        await stdout.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> SetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key) || request.Value is null)
        {
            await stderr.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
            await stderr.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> UnsetAsync(string configPath, ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Key))
        {
            await stderr.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = runtime.NormalizeConfigKey(request.Key);
        var workspaceScope = runtime.ResolveWorkspaceScope(request, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
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
            await stderr.WriteLineAsync(unsetResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ResolveVolumeAsync(ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(request.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(runtime.ExpandHomePath(request.Workspace));

        var volume = await runtime.ResolveDataVolumeAsync(workspace, request.Key, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return 1;
        }

        await stdout.WriteLineAsync(volume).ConfigureAwait(false);
        return 0;
    }
}
