using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService : CaiRuntimeSupport
{
    private async Task<int> RunParsedConfigCommandAsync(ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.Equals(parsed.Action, "resolve-volume", StringComparison.Ordinal))
        {
            return await ConfigResolveVolumeAsync(parsed, cancellationToken).ConfigureAwait(false);
        }

        var configPath = ResolveConfigPath(parsed.Workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        return parsed.Action switch
        {
            "list" => await ConfigListAsync(configPath, cancellationToken).ConfigureAwait(false),
            "get" => await ConfigGetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "set" => await ConfigSetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "unset" => await ConfigUnsetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }

    private async Task<int> ConfigListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigGetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            var wsResult = await RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspaceScope.Workspace),
                cancellationToken).ConfigureAwait(false);
            if (wsResult.ExitCode != 0)
            {
                return 1;
            }

            using var wsJson = JsonDocument.Parse(wsResult.StandardOutput);
            if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
                wsJson.RootElement.TryGetProperty(parsed.Key, out var wsValue))
            {
                await stdout.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
                return 0;
            }

            return 1;
        }

        var getResult = await RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, normalizedKey),
            cancellationToken).ConfigureAwait(false);

        if (getResult.ExitCode != 0)
        {
            return 1;
        }

        await stdout.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigSetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key) || parsed.Value is null)
        {
            await stderr.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult setResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            setResult = await RunTomlAsync(
                () => TomlCommandProcessor.SetWorkspaceKey(configPath, workspaceScope.Workspace, parsed.Key, parsed.Value),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            setResult = await RunTomlAsync(
                () => TomlCommandProcessor.SetKey(configPath, normalizedKey, parsed.Value),
                cancellationToken).ConfigureAwait(false);
        }

        if (setResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigUnsetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult unsetResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            unsetResult = await RunTomlAsync(
                () => TomlCommandProcessor.UnsetWorkspaceKey(configPath, workspaceScope.Workspace, parsed.Key),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            unsetResult = await RunTomlAsync(
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

    private async Task<int> ConfigResolveVolumeAsync(ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(parsed.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(parsed.Workspace));

        var volume = await ResolveDataVolumeAsync(workspace, parsed.Key, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return 1;
        }

        await stdout.WriteLineAsync(volume).ConfigureAwait(false);
        return 0;
    }
}
