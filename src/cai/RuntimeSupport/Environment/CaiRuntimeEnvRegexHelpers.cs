using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimeEnvRegexHelpers
{
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*$", RegexOptions.CultureInvariant)]
    internal static partial Regex EnvVarNameRegex();
}
