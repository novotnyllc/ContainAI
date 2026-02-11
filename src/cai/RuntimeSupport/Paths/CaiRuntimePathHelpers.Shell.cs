namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimePathHelpers
{
    internal static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);
}
