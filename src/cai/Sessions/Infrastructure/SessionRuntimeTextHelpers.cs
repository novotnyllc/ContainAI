namespace ContainAI.Cli.Host;

internal static class SessionRuntimeTextHelpers
{
    internal static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\\''", StringComparison.Ordinal);

    internal static string ReplaceFirstToken(string knownHostsLine, string hostToken)
    {
        var firstSpace = knownHostsLine.IndexOf(' ');
        return firstSpace <= 0
            ? knownHostsLine
            : hostToken + knownHostsLine[firstSpace..];
    }

    internal static string NormalizeNoValue(string value)
    {
        var trimmed = value.Trim();
        return string.Equals(trimmed, "<no value>", StringComparison.Ordinal) ? string.Empty : trimmed;
    }

    internal static string SanitizeNameComponent(string value, string fallback)
        => ContainerNameGenerator.SanitizeNameComponent(value, fallback);

    internal static string SanitizeHostname(string value)
    {
        var normalized = value.ToLowerInvariant().Replace('_', '-');
        var chars = normalized.Where(static ch => char.IsAsciiLetterOrDigit(ch) || ch == '-').ToArray();
        var cleaned = new string(chars);
        while (cleaned.Contains("--", StringComparison.Ordinal))
        {
            cleaned = cleaned.Replace("--", "-", StringComparison.Ordinal);
        }

        cleaned = cleaned.Trim('-');
        if (cleaned.Length > 63)
        {
            cleaned = cleaned[..63].TrimEnd('-');
        }

        return string.IsNullOrWhiteSpace(cleaned) ? "container" : cleaned;
    }

    internal static string TrimTrailingDash(string value) => ContainerNameGenerator.TrimTrailingDash(value);

    internal static string TrimOrFallback(string? value, string fallback)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? fallback : trimmed;
    }
}
