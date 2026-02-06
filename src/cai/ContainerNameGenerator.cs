using System.Security.Cryptography;
using System.Text;

namespace ContainAI.Cli.Host;

internal static class ContainerNameGenerator
{
    public static string Compose(string repoName, string branchName)
    {
        var normalizedBranch = string.IsNullOrWhiteSpace(branchName) || string.Equals(branchName, "HEAD", StringComparison.Ordinal)
            ? "detached"
            : branchName;

        var branchLeaf = normalizedBranch.Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? normalizedBranch;
        var repo = SanitizeNameComponent(repoName, "repo");
        var branch = SanitizeNameComponent(branchLeaf, "branch");

        var repoKeep = repo.Length;
        var branchKeep = branch.Length;
        const int maxCombined = 23;
        while (repoKeep + branchKeep > maxCombined)
        {
            if (repoKeep >= branchKeep && repoKeep > 1)
            {
                repoKeep--;
            }
            else if (branchKeep > 1)
            {
                branchKeep--;
            }
            else
            {
                break;
            }
        }

        repo = TrimTrailingDash(repo[..repoKeep]);
        branch = TrimTrailingDash(branch[..branchKeep]);
        if (string.IsNullOrWhiteSpace(repo))
        {
            repo = "repo";
        }

        if (string.IsNullOrWhiteSpace(branch))
        {
            branch = "branch";
        }

        return $"{repo}-{branch}";
    }

    public static string GenerateLegacy(string workspace)
    {
        var normalized = Path.GetFullPath(workspace).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(normalized));
        var hash = Convert.ToHexString(bytes).ToLowerInvariant();
        return $"containai-{hash[..12]}";
    }

    public static string SanitizeNameComponent(string value, string fallback)
    {
        var normalized = value.ToLowerInvariant().Replace('/', '-');
        var chars = normalized.Where(static ch => char.IsAsciiLetterOrDigit(ch) || ch == '-').ToArray();
        var cleaned = new string(chars);
        while (cleaned.Contains("--", StringComparison.Ordinal))
        {
            cleaned = cleaned.Replace("--", "-", StringComparison.Ordinal);
        }

        cleaned = cleaned.Trim('-');
        return string.IsNullOrWhiteSpace(cleaned) ? fallback : cleaned;
    }

    public static string TrimTrailingDash(string value)
    {
        return value.TrimEnd('-');
    }
}
