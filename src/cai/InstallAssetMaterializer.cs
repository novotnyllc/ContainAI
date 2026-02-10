namespace ContainAI.Cli.Host;

internal interface IInstallAssetMaterializer
{
    InstallAssetMaterializationResult Materialize(string installDir, string homeDirectory);
}

internal sealed partial class InstallAssetMaterializer : IInstallAssetMaterializer
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
}

internal readonly record struct InstallAssetMaterializationResult(
    int ManifestFilesWritten,
    int TemplateFilesWritten,
    int ExampleFilesWritten,
    bool WroteDefaultConfig);
