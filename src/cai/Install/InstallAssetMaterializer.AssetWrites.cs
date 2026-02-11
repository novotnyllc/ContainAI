namespace ContainAI.Cli.Host;

internal sealed partial class InstallAssetMaterializer
{
    private static int WriteManifests(string installDir)
    {
        var manifestsDir = Path.Combine(installDir, "manifests");
        Directory.CreateDirectory(manifestsDir);

        var count = 0;
        foreach (var (name, content) in BuiltInAssets.EnumerateByPrefix("manifest:").OrderBy(static pair => pair.Name, StringComparer.Ordinal))
        {
            var path = Path.Combine(manifestsDir, name);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, EnsureTrailingNewLine(content));
            count++;
        }

        return count;
    }

    private static int WriteTemplateAssets(string installDir)
    {
        var count = 0;
        foreach (var (name, content) in BuiltInAssets.EnumerateByPrefix("template:").OrderBy(static pair => pair.Name, StringComparer.Ordinal))
        {
            var path = Path.Combine(installDir, name.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, EnsureTrailingNewLine(content));
            count++;
        }

        return count;
    }

    private static int WriteExamples(string homeDirectory)
    {
        var examplesDir = Path.Combine(homeDirectory, ".config", "containai", "examples");
        Directory.CreateDirectory(examplesDir);

        var count = 0;
        foreach (var (name, content) in BuiltInAssets.EnumerateByPrefix("example:").OrderBy(static pair => pair.Name, StringComparer.Ordinal))
        {
            var path = Path.Combine(examplesDir, name);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, EnsureTrailingNewLine(content));
            count++;
        }

        return count;
    }
}
