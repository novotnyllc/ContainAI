namespace ContainAI.Cli.Host;

internal interface IInstallAssetMaterializer
{
    InstallAssetMaterializationResult Materialize(string installDir, string homeDirectory);
}

internal sealed class InstallAssetMaterializer : IInstallAssetMaterializer
{
    public InstallAssetMaterializationResult Materialize(string installDir, string homeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(installDir);
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);

        var manifestsWritten = WriteManifests(installDir);
        var templateFilesWritten = WriteTemplateAssets(installDir);
        var examplesWritten = WriteExamples(homeDirectory);
        var defaultConfigWritten = WriteDefaultConfig(homeDirectory);

        return new InstallAssetMaterializationResult(
            manifestsWritten,
            templateFilesWritten,
            examplesWritten,
            defaultConfigWritten);
    }

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

    private static bool WriteDefaultConfig(string homeDirectory)
    {
        if (!BuiltInAssets.TryGet("example:default-config.toml", out var content))
        {
            return false;
        }

        var configDir = Path.Combine(homeDirectory, ".config", "containai");
        var configPath = Path.Combine(configDir, "config.toml");
        if (File.Exists(configPath))
        {
            return false;
        }

        Directory.CreateDirectory(configDir);
        File.WriteAllText(configPath, EnsureTrailingNewLine(content));
        return true;
    }

    private static string EnsureTrailingNewLine(string content)
        => content.EndsWith('\n') ? content : content + Environment.NewLine;
}

internal readonly record struct InstallAssetMaterializationResult(
    int ManifestFilesWritten,
    int TemplateFilesWritten,
    int ExampleFilesWritten,
    bool WroteDefaultConfig);
