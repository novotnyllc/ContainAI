namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestPlanBuilder
{
    ManifestImportPlan Create(string sourceRoot, ManifestEntry entry);
}

internal readonly record struct ManifestImportPlan(
    string SourceAbsolutePath,
    bool SourceExists,
    bool IsDirectory,
    string NormalizedSource,
    string NormalizedTarget);

internal sealed class ImportManifestPlanBuilder : IImportManifestPlanBuilder
{
    public ManifestImportPlan Create(string sourceRoot, ManifestEntry entry)
    {
        var sourceAbsolutePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourceAbsolutePath) || File.Exists(sourceAbsolutePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal) && Directory.Exists(sourceAbsolutePath);

        return new(
            sourceAbsolutePath,
            sourceExists,
            isDirectory,
            NormalizeManifestPath(entry.Source),
            NormalizeManifestPath(entry.Target));
    }

    private static string NormalizeManifestPath(string path)
        => path.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
}
