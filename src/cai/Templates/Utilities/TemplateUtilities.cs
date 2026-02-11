using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal static partial class TemplateUtilities
{
    private static readonly Regex TemplateNameRegex = TemplateNameRegexFactory();

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$", RegexOptions.CultureInvariant)]
    private static partial Regex TemplateNameRegexFactory();

    public static string ResolveTemplatesDirectory(string homeDirectory)
    {
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(homeDirectory, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "templates");
    }

    public static string ResolveTemplateDockerfilePath(string homeDirectory, string? templateName = null)
    {
        var name = string.IsNullOrWhiteSpace(templateName) ? "default" : templateName;
        return Path.Combine(ResolveTemplatesDirectory(homeDirectory), name, "Dockerfile");
    }

    public static bool IsValidTemplateName(string templateName) => !string.IsNullOrWhiteSpace(templateName) && TemplateNameRegex.IsMatch(templateName);

    public static string ComputeTemplateFingerprint(string dockerfileContent)
    {
        var bytes = Encoding.UTF8.GetBytes(dockerfileContent);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public static bool TryUpgradeDockerfile(string content, out string updated)
    {
        updated = content;
        if (content.Contains("${BASE_IMAGE}", StringComparison.Ordinal) &&
            content.Contains("ARG BASE_IMAGE", StringComparison.Ordinal))
        {
            return false;
        }

        var lines = content.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            var trimmed = lines[index].TrimStart();
            if (!trimmed.StartsWith("FROM ", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var fromPayload = trimmed[5..].Trim();
            if (string.IsNullOrWhiteSpace(fromPayload))
            {
                return false;
            }

            string baseImage;
            string? stage = null;
            var asIndex = fromPayload.IndexOf(" AS ", StringComparison.OrdinalIgnoreCase);
            if (asIndex > 0)
            {
                baseImage = fromPayload[..asIndex].Trim();
                stage = fromPayload[(asIndex + 4)..].Trim();
            }
            else
            {
                baseImage = fromPayload;
            }

            var indent = lines[index][..(lines[index].Length - trimmed.Length)];
            var fromReplacement = string.IsNullOrWhiteSpace(stage)
                ? $"{indent}FROM ${{BASE_IMAGE}}"
                : $"{indent}FROM ${{BASE_IMAGE}} AS {stage}";

            var replacement = new List<string>
            {
                $"{indent}ARG BASE_IMAGE={baseImage}",
                fromReplacement,
            };

            lines[index] = string.Join("\n", replacement);
            updated = string.Join("\n", lines);
            if (content.EndsWith('\n') && !updated.EndsWith('\n'))
            {
                updated += "\n";
            }

            return true;
        }

        return false;
    }
}
