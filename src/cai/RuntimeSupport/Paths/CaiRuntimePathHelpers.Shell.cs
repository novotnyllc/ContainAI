namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static partial class CaiRuntimePathHelpers
{
    internal static string EscapeForSingleQuotedShell(string value)
        => value.Replace("'", "'\"'\"'", StringComparison.Ordinal);
}
