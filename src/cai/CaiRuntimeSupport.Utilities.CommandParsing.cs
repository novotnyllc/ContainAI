using System.Text.Json;

namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static async Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    protected async Task<string?> ResolveWorkspaceContainerNameAsync(string workspace, CancellationToken cancellationToken)
    {
        var configPath = ResolveConfigPath(workspace);
        if (File.Exists(configPath))
        {
            var workspaceResult = await RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
                cancellationToken).ConfigureAwait(false);

            if (workspaceResult.ExitCode == 0 && !string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
            {
                using var json = JsonDocument.Parse(workspaceResult.StandardOutput);
                if (json.RootElement.ValueKind == JsonValueKind.Object &&
                    json.RootElement.TryGetProperty("container_name", out var containerNameElement))
                {
                    var configuredName = containerNameElement.GetString();
                    if (!string.IsNullOrWhiteSpace(configuredName))
                    {
                        var inspect = await DockerCaptureAsync(
                            ["inspect", "--type", "container", configuredName],
                            cancellationToken).ConfigureAwait(false);
                        if (inspect.ExitCode == 0)
                        {
                            return configuredName;
                        }
                    }
                }
            }
        }

        var byLabel = await DockerCaptureAsync(
            ["ps", "-aq", "--filter", $"label=containai.workspace={workspace}"],
            cancellationToken).ConfigureAwait(false);

        if (byLabel.ExitCode != 0)
        {
            return null;
        }

        var ids = byLabel.StandardOutput
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (ids.Length == 0)
        {
            return null;
        }

        if (ids.Length > 1)
        {
            await stderr.WriteLineAsync($"Multiple containers found for workspace: {workspace}").ConfigureAwait(false);
            return null;
        }

        var nameResult = await DockerCaptureAsync(
            ["inspect", "--format", "{{.Name}}", ids[0]],
            cancellationToken).ConfigureAwait(false);

        if (nameResult.ExitCode != 0)
        {
            return null;
        }

        return nameResult.StandardOutput.Trim().TrimStart('/');
    }
}
