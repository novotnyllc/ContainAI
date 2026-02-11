using System.Security.Cryptography;
using System.Text;

namespace ContainAI.Cli.Host;

internal static partial class TemplateUtilities
{
    public static bool IsValidTemplateName(string templateName) => !string.IsNullOrWhiteSpace(templateName) && TemplateNameRegex.IsMatch(templateName);

    public static string ComputeTemplateFingerprint(string dockerfileContent)
    {
        var bytes = Encoding.UTF8.GetBytes(dockerfileContent);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
