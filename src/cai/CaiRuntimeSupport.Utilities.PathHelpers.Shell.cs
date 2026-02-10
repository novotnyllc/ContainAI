namespace ContainAI.Cli.Host;

internal static partial class CaiRuntimePathHelpers
{
    internal static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);
}
