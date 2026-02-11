using ContainAI.Cli.Host.RuntimeSupport.Docker;

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

internal sealed class ImportManifestCopyOperations : IImportManifestCopyOperations
{
    private readonly TextWriter stderr;

    public ImportManifestCopyOperations(TextWriter standardOutput, TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
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
        var result = await CaiRuntimeDockerHelpers.DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode == 0)
        {
            return 0;
        }

        var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
        await stderr.WriteLineAsync(errorOutput.Trim()).ConfigureAwait(false);
        return 1;
    }

    private static List<string> BuildManifestRsyncArguments(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan)
    {
        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{sourceRoot}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (entry.Flags.Contains('m', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--delete");
        }

        if (!noExcludes && entry.Flags.Contains('x', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--exclude=.system/");
        }

        if (!noExcludes && entry.Flags.Contains('p', StringComparison.Ordinal) && excludePriv)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (importPlan.IsDirectory)
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource.TrimEnd('/')}/");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource}");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget}");
        }

        return rsyncArgs;
    }

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
