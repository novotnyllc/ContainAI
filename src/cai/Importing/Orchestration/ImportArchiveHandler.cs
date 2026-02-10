using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class ImportArchiveHandler : CaiRuntimeSupport
{
    private readonly IImportTransferOperations transferOperations;

    public ImportArchiveHandler(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportTransferOperations transferOperations)
        : base(standardOutput, standardError)
        => this.transferOperations = transferOperations ?? throw new ArgumentNullException(nameof(transferOperations));

    public async Task<int> HandleArchiveImportAsync(
        ImportCommandOptions options,
        string sourcePath,
        string volume,
        bool excludePriv,
        IReadOnlyList<ManifestEntry> manifestEntries,
        CancellationToken cancellationToken)
    {
        if (!sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
        {
            await stderr.WriteLineAsync($"Unsupported import source file type: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        if (!options.DryRun)
        {
            var restoreCode = await transferOperations
                .RestoreArchiveImportAsync(volume, sourcePath, excludePriv, cancellationToken)
                .ConfigureAwait(false);
            if (restoreCode != 0)
            {
                return restoreCode;
            }

            var applyOverrideCode = await transferOperations.ApplyImportOverridesAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (applyOverrideCode != 0)
            {
                return applyOverrideCode;
            }
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }
}
