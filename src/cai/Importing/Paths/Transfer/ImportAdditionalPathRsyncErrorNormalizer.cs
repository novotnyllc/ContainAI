namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathRsyncErrorNormalizer
{
    string Normalize(string standardOutput, string standardError);
}

internal sealed class ImportAdditionalPathRsyncErrorNormalizer : IImportAdditionalPathRsyncErrorNormalizer
{
    public string Normalize(string standardOutput, string standardError)
    {
        var errorOutput = string.IsNullOrWhiteSpace(standardError) ? standardOutput : standardError;
        var normalizedError = errorOutput.Trim();

        if (normalizedError.Contains("could not make way for new symlink", StringComparison.OrdinalIgnoreCase) &&
            !normalizedError.Contains("cannot delete non-empty directory", StringComparison.OrdinalIgnoreCase))
        {
            normalizedError += $"{System.Environment.NewLine}cannot delete non-empty directory";
        }

        return normalizedError;
    }
}
