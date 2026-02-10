namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestCopyOperations
{
    Task<int> CopyManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan,
        CancellationToken cancellationToken);
}

internal sealed partial class ImportManifestCopyOperations : CaiRuntimeSupport
    , IImportManifestCopyOperations
{
    public ImportManifestCopyOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> CopyManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan,
        CancellationToken cancellationToken)
    {
        var rsyncArgs = BuildManifestRsyncArguments(volume, sourceRoot, entry, excludePriv, noExcludes, importPlan);
        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode == 0)
        {
            return 0;
        }

        var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
        await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
        return 1;
    }
}
