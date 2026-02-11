using ContainAI.Cli.Host.Importing.Transfer;

namespace ContainAI.Cli.Host;

internal static class CaiImportTransferDependenciesFactory
{
    public static CaiImportTransferDependencies Create(TextWriter standardOutput, TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);

        return new CaiImportTransferDependencies(
            new ImportArchiveTransferOperations(standardOutput, standardError),
            new ImportManifestTransferOperations(standardOutput, standardError),
            new ImportOverrideTransferOperations(standardOutput, standardError));
    }
}
