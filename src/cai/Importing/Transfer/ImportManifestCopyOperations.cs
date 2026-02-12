using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestCopyOperations : IImportManifestCopyOperations
{
    private readonly TextWriter stderr;
    private readonly IImportManifestRsyncCommandBuilder rsyncCommandBuilder;

    public ImportManifestCopyOperations(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ImportManifestRsyncCommandBuilder())
    {
    }

    internal ImportManifestCopyOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportManifestRsyncCommandBuilder rsyncCommandBuilder)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.rsyncCommandBuilder = rsyncCommandBuilder ?? throw new ArgumentNullException(nameof(rsyncCommandBuilder));
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
        var rsyncArgs = rsyncCommandBuilder.Build(volume, sourceRoot, entry, excludePriv, noExcludes, importPlan);
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode == 0)
        {
            return 0;
        }

        var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
        await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
        return 1;
    }
}
