namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentVariableMerger
{
    Dictionary<string, string> Merge(
        Dictionary<string, string> fileVariables,
        IReadOnlyDictionary<string, string> hostVariables);
}
