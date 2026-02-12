namespace ContainAI.Cli.Host;

internal interface IInstallAssetMaterializer
{
    InstallAssetMaterializationResult Materialize(string installDir, string homeDirectory);
}
