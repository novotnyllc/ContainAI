namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\\''", StringComparison.Ordinal);

    public static string ReplaceFirstToken(string knownHostsLine, string hostToken)
    {
        var firstSpace = knownHostsLine.IndexOf(' ');
        if (firstSpace <= 0)
        {
            return knownHostsLine;
        }

        return hostToken + knownHostsLine[firstSpace..];
    }

    public static string NormalizeNoValue(string value)
    {
        var trimmed = value.Trim();
        return string.Equals(trimmed, "<no value>", StringComparison.Ordinal) ? string.Empty : trimmed;
    }

    public static string SanitizeNameComponent(string value, string fallback) => ContainerNameGenerator.SanitizeNameComponent(value, fallback);

    public static string SanitizeHostname(string value)
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

    public static string TrimTrailingDash(string value) => ContainerNameGenerator.TrimTrailingDash(value);

    public static string GenerateWorkspaceVolumeName(string workspace)
    {
        var repo = SanitizeNameComponent(Path.GetFileName(Path.TrimEndingDirectorySeparator(workspace)), "workspace");
        var branch = "nogit";
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyyMMddHHmmss");

        try
        {
            var result = CliWrapProcessRunner
                .RunCaptureAsync(
                    "git",
                    ["-C", workspace, "rev-parse", "--abbrev-ref", "HEAD"],
                    CancellationToken.None)
                .WaitAsync(TimeSpan.FromSeconds(2))
                .GetAwaiter()
                .GetResult();

            if (result.ExitCode == 0)
            {
                var branchValue = result.StandardOutput.Trim();
                if (!string.IsNullOrWhiteSpace(branchValue))
                {
                    branch = SanitizeNameComponent(branchValue.Split('/').LastOrDefault() ?? branchValue, "nogit");
                }
            }
        }
        catch (InvalidOperationException)
        {
        }
        catch (IOException)
        {
        }
        catch (TimeoutException)
        {
        }

        return $"{repo}-{branch}-{timestamp}";
    }

    public static string TrimOrFallback(string? value, string fallback)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? fallback : trimmed;
    }
}
