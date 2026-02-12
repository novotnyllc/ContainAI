namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathRsyncErrorNormalizer
{
    string Normalize(string standardOutput, string standardError);
}
