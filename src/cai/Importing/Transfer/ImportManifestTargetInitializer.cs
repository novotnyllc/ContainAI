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

internal sealed partial class ImportManifestTargetInitializer : CaiRuntimeSupport
    , IImportManifestTargetInitializer
{
    public ImportManifestTargetInitializer(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        if (ShouldSkipForNoSecrets(entry, noSecrets))
        {
            return 0;
        }

        var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
        var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
        if (entry.Optional && !sourceExists)
        {
            return 0;
        }

        if (isDirectory)
        {
            var ensureDirectory = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureDirectoryCommand(entry.Target, IsSecretEntry(entry))],
                cancellationToken).ConfigureAwait(false);
            if (ensureDirectory.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureDirectory.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }

            return 0;
        }

        if (!isFile)
        {
            return 0;
        }

        var ensureFile = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureFileCommand(entry)],
            cancellationToken).ConfigureAwait(false);
        if (ensureFile.ExitCode != 0)
        {
            await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
