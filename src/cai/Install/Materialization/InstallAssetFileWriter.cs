namespace ContainAI.Cli.Host;

internal static class InstallAssetFileWriter
{
    public static int WriteByPrefix(string prefix, string destinationRoot, bool replacePathSeparators)
    {
        Directory.CreateDirectory(destinationRoot);

        var count = 0;
        foreach (var (name, content) in BuiltInAssets.EnumerateByPrefix(prefix).OrderBy(static pair => pair.Name, StringComparer.Ordinal))
        {
            var relativePath = replacePathSeparators
                ? name.Replace('/', Path.DirectorySeparatorChar)
                : name;
            var path = Path.Combine(destinationRoot, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, EnsureTrailingNewLine(content));
            count++;
        }

        return count;
    }

    public static string EnsureTrailingNewLine(string content)
        => content.EndsWith('\n') ? content : content + Environment.NewLine;
}
