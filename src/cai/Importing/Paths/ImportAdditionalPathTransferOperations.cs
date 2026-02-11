using ContainAI.Cli.Host;
using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathTransferOperations : IImportAdditionalPathTransferOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IImportAdditionalPathTargetEnsurer targetEnsurer;
    private readonly IImportAdditionalPathRsyncCommandBuilder rsyncCommandBuilder;
    private readonly IImportAdditionalPathRsyncErrorNormalizer rsyncErrorNormalizer;

    public ImportAdditionalPathTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportAdditionalPathTargetEnsurer(standardError),
            new ImportAdditionalPathRsyncCommandBuilder(),
            new ImportAdditionalPathRsyncErrorNormalizer())
    {
    }

    internal ImportAdditionalPathTransferOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportAdditionalPathTargetEnsurer importAdditionalPathTargetEnsurer,
        IImportAdditionalPathRsyncCommandBuilder importAdditionalPathRsyncCommandBuilder,
        IImportAdditionalPathRsyncErrorNormalizer importAdditionalPathRsyncErrorNormalizer)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        targetEnsurer = importAdditionalPathTargetEnsurer ?? throw new ArgumentNullException(nameof(importAdditionalPathTargetEnsurer));
        rsyncCommandBuilder = importAdditionalPathRsyncCommandBuilder ?? throw new ArgumentNullException(nameof(importAdditionalPathRsyncCommandBuilder));
        rsyncErrorNormalizer = importAdditionalPathRsyncErrorNormalizer ?? throw new ArgumentNullException(nameof(importAdditionalPathRsyncErrorNormalizer));
    }

    public async Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync additional path {additionalPath.SourcePath} -> {additionalPath.TargetPath}").ConfigureAwait(false);
            return 0;
        }

        if (verbose && noExcludes)
        {
            await stdout.WriteLineAsync("[INFO] --no-excludes does not disable .priv. filtering for additional paths").ConfigureAwait(false);
        }

        var ensureResult = await targetEnsurer.EnsureAsync(volume, additionalPath, cancellationToken).ConfigureAwait(false);
        if (ensureResult != 0)
        {
            return 1;
        }

        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            rsyncCommandBuilder.Build(volume, additionalPath),
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var normalizedError = rsyncErrorNormalizer.Normalize(result.StandardOutput, result.StandardError);
            await stderr.WriteLineAsync(normalizedError).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
