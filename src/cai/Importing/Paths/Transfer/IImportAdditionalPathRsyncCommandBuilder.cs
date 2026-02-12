namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathRsyncCommandBuilder
{
    IReadOnlyList<string> Build(string volume, ImportAdditionalPath additionalPath);
}
