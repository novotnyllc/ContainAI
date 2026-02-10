namespace ContainAI.Cli.Host;

internal static class CaiRuntimeParseAndTimeHelpers
{
    internal static async Task<RuntimeProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = operation();
        return await Task
            .FromResult(new RuntimeProcessResult(result.ExitCode, result.StandardOutput, result.StandardError))
            .ConfigureAwait(false);
    }

    internal static string NormalizeConfigKey(string key)
        => string.Equals(key, "agent", StringComparison.Ordinal)
            ? "agent.default"
            : key;

    internal static (string? Workspace, string? Error) ResolveWorkspaceScope(bool isGlobal, string? workspace, string normalizedKey)
    {
        if (!string.Equals(normalizedKey, "data_volume", StringComparison.Ordinal))
        {
            return (workspace, null);
        }

        if (isGlobal)
        {
            return (null, "data_volume is workspace-scoped and cannot be set globally");
        }

        if (string.IsNullOrWhiteSpace(workspace))
        {
            workspace = Directory.GetCurrentDirectory();
        }

        return (Path.GetFullPath(workspace), null);
    }

    internal static bool TryParseAgeDuration(string value, out TimeSpan duration)
    {
        duration = default;
        if (string.IsNullOrWhiteSpace(value) || value.Length < 2)
        {
            return false;
        }

        var suffix = value[^1];
        if (!int.TryParse(value[..^1], out var amount) || amount < 0)
        {
            return false;
        }

        duration = suffix switch
        {
            'd' or 'D' => TimeSpan.FromDays(amount),
            'h' or 'H' => TimeSpan.FromHours(amount),
            _ => default,
        };

        return duration != default || amount == 0;
    }

    internal static DateTimeOffset? ParseGcReferenceTime(string finishedAtRaw, string createdRaw)
    {
        if (!string.IsNullOrWhiteSpace(finishedAtRaw) &&
            !string.Equals(finishedAtRaw, "0001-01-01T00:00:00Z", StringComparison.Ordinal) &&
            DateTimeOffset.TryParse(finishedAtRaw, out var finishedAt))
        {
            return finishedAt;
        }

        return DateTimeOffset.TryParse(createdRaw, out var created) ? created : null;
    }
}
