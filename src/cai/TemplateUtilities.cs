using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class TemplateUtilities
{
    private static readonly Regex TemplateNameRegex = TemplateNameRegexFactory();

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex TemplateNameRegexFactory();
}
