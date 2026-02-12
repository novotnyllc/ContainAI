namespace ContainAI.Cli.Host;

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
        return InstallAssetFileWriter.WriteByPrefix("manifest:", manifestsDir, replacePathSeparators: false);
    }

    private static int WriteTemplateAssets(string installDir)
        => InstallAssetFileWriter.WriteByPrefix("template:", installDir, replacePathSeparators: true);

    private static int WriteExamples(string homeDirectory)
    {
        var examplesDir = Path.Combine(homeDirectory, ".config", "containai", "examples");
        return InstallAssetFileWriter.WriteByPrefix("example:", examplesDir, replacePathSeparators: false);
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
        File.WriteAllText(configPath, InstallAssetFileWriter.EnsureTrailingNewLine(content));
        return true;
    }
}

internal readonly record struct InstallAssetMaterializationResult(
    int ManifestFilesWritten,
    int TemplateFilesWritten,
    int ExampleFilesWritten,
    bool WroteDefaultConfig);
