namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestPlanBuilder
{
    ManifestImportPlan Create(string sourceRoot, ManifestEntry entry);
}
