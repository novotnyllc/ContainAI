using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportOverrideTransferOperations : IImportOverrideTransferOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public ImportOverrideTransferOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> ApplyImportOverridesAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var overridesDirectory = Path.Combine(CaiRuntimeHomePathHelpers.ResolveHomeDirectory(), ".config", "containai", "import-overrides");
        if (!Directory.Exists(overridesDirectory))
        {
            return 0;
        }

        var overrideFiles = GetOverrideFiles(overridesDirectory);
        foreach (var file in overrideFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var preparedOverride = await PrepareOverrideFileAsync(
                overridesDirectory,
                file,
                manifestEntries,
                noSecrets,
                verbose).ConfigureAwait(false);
            if (preparedOverride is null)
            {
                continue;
            }

            if (dryRun)
            {
                await stdout.WriteLineAsync(
                    $"[DRY-RUN] Would apply override {preparedOverride.Value.RelativePath} -> {preparedOverride.Value.MappedTargetPath}")
                    .ConfigureAwait(false);
                continue;
            }

            var copyCode = await CopyPreparedOverrideAsync(
                volume,
                overridesDirectory,
                preparedOverride.Value,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        return 0;
    }

    private readonly record struct PreparedOverride(string RelativePath, string MappedTargetPath);

    private static string[] GetOverrideFiles(string overridesDirectory)
        => Directory.EnumerateFiles(overridesDirectory, "*", SearchOption.AllDirectories)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();

    private async Task<PreparedOverride?> PrepareOverrideFileAsync(
        string overridesDirectory,
        string file,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose)
    {
        if (CaiRuntimePathHelpers.IsSymbolicLinkPath(file))
        {
            await stderr.WriteLineAsync($"Skipping override symlink: {file}").ConfigureAwait(false);
            return null;
        }

        var relative = NormalizeOverrideRelativePath(overridesDirectory, file);
        if (!CaiRuntimePathHelpers.TryMapSourcePathToTarget(relative, manifestEntries, out var mappedTarget, out var mappedFlags))
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"Skipping unmapped override path: {relative}").ConfigureAwait(false);
            }

            return null;
        }

        if (ShouldSkipOverrideForNoSecrets(mappedFlags, noSecrets))
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"Skipping secret override due to --no-secrets: {relative}").ConfigureAwait(false);
            }

            return null;
        }

        return new PreparedOverride(relative, mappedTarget);
    }

    private static string NormalizeOverrideRelativePath(string overridesDirectory, string file)
    {
        var relative = Path.GetRelativePath(overridesDirectory, file).Replace("\\", "/", StringComparison.Ordinal);
        if (!relative.StartsWith('.'))
        {
            relative = "." + relative;
        }

        return relative;
    }

    private async Task<int> CopyPreparedOverrideAsync(
        string volume,
        string overridesDirectory,
        PreparedOverride preparedOverride,
        CancellationToken cancellationToken)
    {
        var copy = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            [
                "run",
                "--rm",
                "-v",
                $"{volume}:/target",
                "-v",
                $"{overridesDirectory}:/override:ro",
                "alpine:3.20",
                "sh",
                "-lc",
                BuildOverrideCopyCommand(preparedOverride.RelativePath, preparedOverride.MappedTargetPath),
            ],
            cancellationToken).ConfigureAwait(false);
        if (copy.ExitCode != 0)
        {
            await stderr.WriteLineAsync(copy.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static bool ShouldSkipOverrideForNoSecrets(string mappedFlags, bool noSecrets)
        => noSecrets && mappedFlags.Contains('s', StringComparison.Ordinal);

    private static string BuildOverrideCopyCommand(string relativePath, string mappedTargetPath)
        => $"src='/override/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(relativePath.TrimStart('/'))}'; " +
           $"dest='/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(mappedTargetPath)}'; " +
           "mkdir -p \"$(dirname \"$dest\")\"; cp -f \"$src\" \"$dest\"; chown 1000:1000 \"$dest\" || true";
}
