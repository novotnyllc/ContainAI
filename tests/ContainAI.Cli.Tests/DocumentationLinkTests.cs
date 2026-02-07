using System.Text.RegularExpressions;
using Xunit;

namespace ContainAI.Cli.Tests;

public sealed partial class DocumentationLinkTests
{
    [Fact]
    [Trait("Category", "Docs")]
    public void MarkdownLinks_ShouldResolve()
    {
        var repositoryRoot = ResolveRepositoryRoot();
        var markdownFiles = EnumerateMarkdownFiles(repositoryRoot).ToArray();
        var errors = new List<string>();

        foreach (var file in markdownFiles)
        {
            ValidateFile(file, markdownFiles, errors);
        }

        Assert.True(errors.Count == 0, string.Join(Environment.NewLine, errors));
    }

    private static string ResolveRepositoryRoot()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "ContainAI.slnx")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new InvalidOperationException("Repository root not found from test base directory.");
    }

    private static IEnumerable<string> EnumerateMarkdownFiles(string repositoryRoot)
    {
        foreach (var file in Directory.EnumerateFiles(Path.Combine(repositoryRoot, "docs"), "*.md", SearchOption.AllDirectories))
        {
            yield return Path.GetFullPath(file);
        }

        foreach (var rootFile in new[] { "README.md", "AGENTS.md", "CONTRIBUTING.md", "SECURITY.md" })
        {
            var fullPath = Path.Combine(repositoryRoot, rootFile);
            if (File.Exists(fullPath))
            {
                yield return Path.GetFullPath(fullPath);
            }
        }
    }

    private static void ValidateFile(string file, IReadOnlyCollection<string> allMarkdownFiles, ICollection<string> errors)
    {
        var markdown = File.ReadAllText(file);
        var lineNumber = 1;

        foreach (var line in markdown.Split('\n'))
        {
            foreach (Match match in MarkdownLinkRegex().Matches(line))
            {
                var target = match.Groups[1].Value.Trim();
                if (string.IsNullOrWhiteSpace(target) || target.StartsWith("!", StringComparison.Ordinal))
                {
                    continue;
                }

                var targetWithoutTitle = StripOptionalTitle(target);
                if (ShouldSkipTarget(targetWithoutTitle))
                {
                    continue;
                }

                ValidateTarget(file, lineNumber, targetWithoutTitle, allMarkdownFiles, errors);
            }

            lineNumber++;
        }
    }

    private static bool ShouldSkipTarget(string target)
    {
        return target.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("ftp://", StringComparison.OrdinalIgnoreCase)
            || target.StartsWith("data:", StringComparison.OrdinalIgnoreCase);
    }

    private static string StripOptionalTitle(string target)
    {
        if (target.StartsWith('<') && target.EndsWith('>'))
        {
            return target[1..^1];
        }

        var quoteIndex = target.IndexOf(" \"", StringComparison.Ordinal);
        return quoteIndex > 0 ? target[..quoteIndex].Trim() : target;
    }

    private static void ValidateTarget(
        string sourceFile,
        int lineNumber,
        string target,
        IReadOnlyCollection<string> allMarkdownFiles,
        ICollection<string> errors)
    {
        var anchorIndex = target.IndexOf('#');
        var relativePath = anchorIndex >= 0 ? target[..anchorIndex] : target;
        var anchor = anchorIndex >= 0 ? target[(anchorIndex + 1)..] : string.Empty;

        if (relativePath.StartsWith("/", StringComparison.Ordinal))
        {
            errors.Add($"{Relative(sourceFile)}:{lineNumber}: absolute link path is not allowed: {target}");
            return;
        }

        var resolvedPath = string.IsNullOrWhiteSpace(relativePath)
            ? sourceFile
            : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourceFile)!, Uri.UnescapeDataString(relativePath)));

        if (!File.Exists(resolvedPath))
        {
            errors.Add($"{Relative(sourceFile)}:{lineNumber}: target file does not exist: {target}");
            return;
        }

        if (Path.GetExtension(resolvedPath).Equals(".md", StringComparison.OrdinalIgnoreCase)
            && allMarkdownFiles.Contains(resolvedPath, StringComparer.OrdinalIgnoreCase)
            && !string.IsNullOrWhiteSpace(anchor)
            && !AnchorExists(resolvedPath, anchor))
        {
            errors.Add($"{Relative(sourceFile)}:{lineNumber}: anchor '{anchor}' not found in {Relative(resolvedPath)}");
        }
    }

    private static bool AnchorExists(string markdownFile, string anchor)
    {
        var headingAnchors = ExtractAnchors(markdownFile);
        return headingAnchors.Contains(anchor, StringComparer.Ordinal);
    }

    private static IReadOnlySet<string> ExtractAnchors(string markdownFile)
    {
        var anchors = new HashSet<string>(StringComparer.Ordinal);
        var duplicateCounts = new Dictionary<string, int>(StringComparer.Ordinal);
        var inCodeBlock = false;

        foreach (var line in File.ReadLines(markdownFile))
        {
            if (FenceRegex().IsMatch(line))
            {
                inCodeBlock = !inCodeBlock;
                continue;
            }

            if (inCodeBlock)
            {
                continue;
            }

            var heading = HeadingRegex().Match(line);
            if (!heading.Success)
            {
                continue;
            }

            var slug = ToGitHubAnchor(heading.Groups[2].Value);
            if (string.IsNullOrWhiteSpace(slug))
            {
                continue;
            }

            if (!duplicateCounts.TryAdd(slug, 1))
            {
                var count = duplicateCounts[slug];
                anchors.Add($"{slug}-{count}");
                duplicateCounts[slug] = count + 1;
                continue;
            }

            anchors.Add(slug);
        }

        return anchors;
    }

    private static string ToGitHubAnchor(string heading)
    {
        var slug = heading.Trim().ToLowerInvariant();
        slug = NonAnchorCharacterRegex().Replace(slug, string.Empty);
        slug = slug.Replace(' ', '-');
        slug = slug.Trim('-');
        return slug;
    }

    private static string Relative(string path)
    {
        var repositoryRoot = ResolveRepositoryRoot();
        return Path.GetRelativePath(repositoryRoot, path).Replace('\\', '/');
    }

    [GeneratedRegex("(?<!\\!)\\[[^\\]]*\\]\\(([^)]+)\\)", RegexOptions.Compiled)]
    private static partial Regex MarkdownLinkRegex();

    [GeneratedRegex("^[\\s]*([#]{1,6})[\\s]+(.+)$", RegexOptions.Compiled)]
    private static partial Regex HeadingRegex();

    [GeneratedRegex("^[\\s]*([~]{3,}|`{3,})", RegexOptions.Compiled)]
    private static partial Regex FenceRegex();

    [GeneratedRegex("[^a-z0-9 _-]", RegexOptions.Compiled)]
    private static partial Regex NonAnchorCharacterRegex();
}
