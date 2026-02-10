namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string EscapeForSingleQuotedShell(string value)
        => SessionRuntimeTextHelpers.EscapeForSingleQuotedShell(value);

    public static string ReplaceFirstToken(string knownHostsLine, string hostToken)
        => SessionRuntimeTextHelpers.ReplaceFirstToken(knownHostsLine, hostToken);

    public static string NormalizeNoValue(string value)
        => SessionRuntimeTextHelpers.NormalizeNoValue(value);

    public static string SanitizeNameComponent(string value, string fallback)
        => SessionRuntimeTextHelpers.SanitizeNameComponent(value, fallback);

    public static string SanitizeHostname(string value) => SessionRuntimeTextHelpers.SanitizeHostname(value);

    public static string TrimTrailingDash(string value) => SessionRuntimeTextHelpers.TrimTrailingDash(value);

    public static string GenerateWorkspaceVolumeName(string workspace)
        => SessionRuntimeVolumeNameGenerator.GenerateWorkspaceVolumeName(workspace);

    public static string TrimOrFallback(string? value, string fallback)
        => SessionRuntimeTextHelpers.TrimOrFallback(value, fallback);
}
