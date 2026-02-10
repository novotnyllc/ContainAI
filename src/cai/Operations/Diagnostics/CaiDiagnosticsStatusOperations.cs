namespace ContainAI.Cli.Host;

internal sealed class CaiDiagnosticsStatusOperations : CaiRuntimeSupport
{
    public CaiDiagnosticsStatusOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> RunStatusAsync(
        bool outputJson,
        bool verbose,
        string? workspace,
        string? container,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(workspace) && !string.IsNullOrWhiteSpace(container))
        {
            await stderr.WriteLineAsync("--workspace and --container are mutually exclusive").ConfigureAwait(false);
            return 1;
        }

        var effectiveWorkspace = Path.GetFullPath(ExpandHomePath(workspace ?? Directory.GetCurrentDirectory()));
        if (string.IsNullOrWhiteSpace(container))
        {
            container = await ResolveWorkspaceContainerNameAsync(effectiveWorkspace, cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(container))
            {
                await stderr.WriteLineAsync($"No container found for workspace: {effectiveWorkspace}").ConfigureAwait(false);
                return 1;
            }
        }

        var discoveredContexts = await FindContainerContextsAsync(container, cancellationToken).ConfigureAwait(false);
        if (discoveredContexts.Count == 0)
        {
            await stderr.WriteLineAsync($"Container not found: {container}").ConfigureAwait(false);
            return 1;
        }

        if (discoveredContexts.Count > 1)
        {
            await stderr.WriteLineAsync($"Container '{container}' exists in multiple contexts: {string.Join(", ", discoveredContexts)}").ConfigureAwait(false);
            return 1;
        }

        var context = discoveredContexts[0];

        var managedResult = await DockerCaptureForContextAsync(
            context,
            ["inspect", "--format", "{{index .Config.Labels \"containai.managed\"}}", "--", container],
            cancellationToken).ConfigureAwait(false);
        if (managedResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Failed to inspect container: {container}").ConfigureAwait(false);
            return 1;
        }

        if (!string.Equals(managedResult.StandardOutput.Trim(), "true", StringComparison.Ordinal))
        {
            await stderr.WriteLineAsync($"Container {container} exists but is not managed by ContainAI").ConfigureAwait(false);
            return 1;
        }

        var inspect = await DockerCaptureForContextAsync(
            context,
            ["inspect", "--format", "{{.State.Status}}|{{.Config.Image}}|{{.State.StartedAt}}", "--", container],
            cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            await stderr.WriteLineAsync($"Failed to inspect container: {container}").ConfigureAwait(false);
            return 1;
        }

        var parts = inspect.StandardOutput.Trim().Split('|');
        if (parts.Length < 3)
        {
            await stderr.WriteLineAsync("Unable to parse container status").ConfigureAwait(false);
            return 1;
        }

        var status = parts[0];
        var image = parts[1];
        var startedAt = parts[2];

        string? uptime = null;
        if (string.Equals(status, "running", StringComparison.Ordinal) &&
            DateTimeOffset.TryParse(startedAt, out var started))
        {
            var elapsed = DateTimeOffset.UtcNow - started;
            if (elapsed.TotalDays >= 1)
            {
                uptime = $"{(int)elapsed.TotalDays}d {elapsed.Hours}h {elapsed.Minutes}m";
            }
            else if (elapsed.TotalHours >= 1)
            {
                uptime = $"{elapsed.Hours}h {elapsed.Minutes}m";
            }
            else
            {
                uptime = $"{Math.Max(0, elapsed.Minutes)}m";
            }
        }

        string? memUsage = null;
        string? memLimit = null;
        string? cpuPercent = null;
        if (string.Equals(status, "running", StringComparison.Ordinal))
        {
            var stats = await DockerCaptureForContextAsync(
                context,
                ["stats", "--no-stream", "--format", "{{.MemUsage}}|{{.CPUPerc}}", "--", container],
                cancellationToken).ConfigureAwait(false);
            if (stats.ExitCode == 0)
            {
                var statsParts = stats.StandardOutput.Trim().Split('|');
                if (statsParts.Length >= 2)
                {
                    cpuPercent = statsParts[1];
                    var memParts = statsParts[0].Split(" / ", StringSplitOptions.TrimEntries);
                    if (memParts.Length == 2)
                    {
                        memUsage = memParts[0];
                        memLimit = memParts[1];
                    }
                }
            }
        }

        if (outputJson)
        {
            var jsonFields = new List<string>
            {
                $"\"container\":\"{EscapeJson(container)}\"",
                $"\"status\":\"{EscapeJson(status)}\"",
                $"\"image\":\"{EscapeJson(image)}\"",
                $"\"context\":\"{EscapeJson(context)}\"",
            };

            if (!string.IsNullOrWhiteSpace(uptime))
            {
                jsonFields.Add($"\"uptime\":\"{EscapeJson(uptime)}\"");
            }

            if (!string.IsNullOrWhiteSpace(memUsage))
            {
                jsonFields.Add($"\"memory_usage\":\"{EscapeJson(memUsage)}\"");
            }

            if (!string.IsNullOrWhiteSpace(memLimit))
            {
                jsonFields.Add($"\"memory_limit\":\"{EscapeJson(memLimit)}\"");
            }

            if (!string.IsNullOrWhiteSpace(cpuPercent))
            {
                jsonFields.Add($"\"cpu_percent\":\"{EscapeJson(cpuPercent)}\"");
            }

            await stdout.WriteLineAsync("{" + string.Join(",", jsonFields) + "}").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync($"Container: {container}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Status: {status}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Image: {image}").ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(uptime))
        {
            await stdout.WriteLineAsync($"  Uptime: {uptime}").ConfigureAwait(false);
        }

        if (verbose)
        {
            await stdout.WriteLineAsync($"  Context: {context}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(memUsage) && !string.IsNullOrWhiteSpace(memLimit))
        {
            await stdout.WriteLineAsync($"  Memory: {memUsage} / {memLimit}").ConfigureAwait(false);
        }

        if (!string.IsNullOrWhiteSpace(cpuPercent))
        {
            await stdout.WriteLineAsync($"  CPU: {cpuPercent}").ConfigureAwait(false);
        }

        return 0;
    }
}
