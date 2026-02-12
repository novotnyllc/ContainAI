namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal sealed class ImportEnvironmentVariableMerger : IImportEnvironmentVariableMerger
{
    public Dictionary<string, string> Merge(
        Dictionary<string, string> fileVariables,
        IReadOnlyDictionary<string, string> hostVariables)
    {
        var merged = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in fileVariables)
        {
            merged[key] = value;
        }

        foreach (var (key, value) in hostVariables)
        {
            merged[key] = value;
        }

        return merged;
    }
}
