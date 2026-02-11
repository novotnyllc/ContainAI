namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetInitializer
{
    Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken);
}

internal sealed class ImportManifestTargetInitializer : IImportManifestTargetInitializer
{
    private readonly IImportManifestTargetCommandBuilder commandBuilder;
    private readonly IImportManifestTargetEnsureExecutor ensureExecutor;

    public ImportManifestTargetInitializer(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportManifestTargetCommandBuilder(),
            new ImportManifestTargetEnsureExecutor(standardError))
    {
    }

    internal ImportManifestTargetInitializer(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportManifestTargetCommandBuilder importManifestTargetCommandBuilder,
        IImportManifestTargetEnsureExecutor importManifestTargetEnsureExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        commandBuilder = importManifestTargetCommandBuilder ?? throw new ArgumentNullException(nameof(importManifestTargetCommandBuilder));
        ensureExecutor = importManifestTargetEnsureExecutor ?? throw new ArgumentNullException(nameof(importManifestTargetEnsureExecutor));
    }

    public Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        if (ImportManifestTargetSkipPolicy.ShouldSkipForNoSecrets(entry, noSecrets))
        {
            return Task.FromResult(0);
        }

        var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
        var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
        if (entry.Optional && !sourceExists)
        {
            return Task.FromResult(0);
        }

        if (isDirectory)
        {
            return ensureExecutor.EnsureAsync(
                volume,
                commandBuilder.BuildEnsureDirectoryCommand(
                    entry.Target,
                    ImportManifestTargetSkipPolicy.IsSecretEntry(entry)),
                cancellationToken);
        }

        if (!isFile)
        {
            return Task.FromResult(0);
        }

        return ensureExecutor.EnsureAsync(
            volume,
            commandBuilder.BuildEnsureFileCommand(entry),
            cancellationToken);
    }
}
