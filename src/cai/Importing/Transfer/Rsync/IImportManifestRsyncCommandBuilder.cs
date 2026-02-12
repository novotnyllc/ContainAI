namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestRsyncCommandBuilder
{
    List<string> Build(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan);
}
