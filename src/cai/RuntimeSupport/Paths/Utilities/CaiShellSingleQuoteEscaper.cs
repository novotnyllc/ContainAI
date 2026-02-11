namespace ContainAI.Cli.Host.RuntimeSupport.Paths.Utilities;

internal static class CaiShellSingleQuoteEscaper
{
    public static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);
}
