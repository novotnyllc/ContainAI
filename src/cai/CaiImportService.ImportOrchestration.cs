using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IImportOrchestrationOperations
{
    Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class CaiImportOrchestrationOperations : CaiRuntimeSupport
    , IImportOrchestrationOperations
{
    private readonly IManifestTomlParser manifestTomlParser;
    private readonly IImportManifestCatalog manifestCatalog;
    private readonly IImportPathOperations pathOperations;
    private readonly IImportTransferOperations transferOperations;
    private readonly IImportEnvironmentOperations environmentOperations;

    public CaiImportOrchestrationOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ManifestTomlParser(),
            new CaiImportManifestCatalog(),
            new CaiImportPathOperations(standardOutput, standardError),
            new CaiImportTransferOperations(standardOutput, standardError),
            new CaiImportEnvironmentOperations(standardOutput, standardError))
    {
    }

    internal CaiImportOrchestrationOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IImportManifestCatalog importManifestCatalog,
        IImportPathOperations importPathOperations,
        IImportTransferOperations importTransferOperations,
        IImportEnvironmentOperations importEnvironmentOperations)
        : base(standardOutput, standardError)
    {
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        manifestCatalog = importManifestCatalog;
        pathOperations = importPathOperations;
        transferOperations = importTransferOperations;
        environmentOperations = importEnvironmentOperations;
    }

    public Task<int> RunImportAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunImportCoreAsync(options, cancellationToken);
    }

    private async Task<int> RunImportCoreAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(options.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(options.Workspace));
        var explicitConfigPath = string.IsNullOrWhiteSpace(options.Config)
            ? null
            : Path.GetFullPath(ExpandHomePath(options.Config));

        if (!string.IsNullOrWhiteSpace(explicitConfigPath) && !File.Exists(explicitConfigPath))
        {
            await stderr.WriteLineAsync($"Config file not found: {explicitConfigPath}").ConfigureAwait(false);
            return 1;
        }

        var volume = await ResolveDataVolumeAsync(workspace, options.DataVolume, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            await stderr.WriteLineAsync("Unable to resolve data volume. Use --data-volume.").ConfigureAwait(false);
            return 1;
        }

        var sourcePath = string.IsNullOrWhiteSpace(options.From)
            ? ResolveHomeDirectory()
            : Path.GetFullPath(ExpandHomePath(options.From));
        if (!File.Exists(sourcePath) && !Directory.Exists(sourcePath))
        {
            await stderr.WriteLineAsync($"Import source not found: {sourcePath}").ConfigureAwait(false);
            return 1;
        }

        var excludePriv = await pathOperations.ResolveImportExcludePrivAsync(workspace, explicitConfigPath, cancellationToken).ConfigureAwait(false);

        await stdout.WriteLineAsync($"Using data volume: {volume}").ConfigureAwait(false);
        if (options.DryRun)
        {
            await stdout.WriteLineAsync($"Dry-run context: {ResolveDockerContextName()}").ConfigureAwait(false);
        }

        if (!options.DryRun)
        {
            var ensureVolume = await DockerCaptureAsync(["volume", "create", volume], cancellationToken).ConfigureAwait(false);
            if (ensureVolume.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        ManifestEntry[] manifestEntries;
        try
        {
            var manifestDirectory = manifestCatalog.ResolveDirectory();
            manifestEntries = manifestTomlParser.Parse(manifestDirectory, includeDisabled: false, includeSourceFile: false)
                .Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal))
                .Where(static entry => !string.IsNullOrWhiteSpace(entry.Source))
                .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
                .ToArray();
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"Failed to load import manifests: {ex.Message}").ConfigureAwait(false);
            return 1;
        }

        if (File.Exists(sourcePath))
        {
            if (!sourcePath.EndsWith(".tgz", StringComparison.OrdinalIgnoreCase))
            {
                await stderr.WriteLineAsync($"Unsupported import source file type: {sourcePath}").ConfigureAwait(false);
                return 1;
            }

            if (!options.DryRun)
            {
                var restoreCode = await transferOperations.RestoreArchiveImportAsync(volume, sourcePath, excludePriv, cancellationToken).ConfigureAwait(false);
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

        var additionalImportPaths = await pathOperations.ResolveAdditionalImportPathsAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);

        if (!options.DryRun)
        {
            var initCode = await transferOperations.InitializeImportTargetsAsync(
                volume,
                sourcePath,
                manifestEntries,
                options.NoSecrets,
                cancellationToken).ConfigureAwait(false);
            if (initCode != 0)
            {
                return initCode;
            }
        }

        foreach (var entry in manifestEntries)
        {
            if (options.NoSecrets && entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                if (options.Verbose)
                {
                    await stderr.WriteLineAsync($"Skipping secret entry: {entry.Source}").ConfigureAwait(false);
                }

                continue;
            }

            var copyCode = await transferOperations.ImportManifestEntryAsync(
                volume,
                sourcePath,
                entry,
                excludePriv,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        if (!options.DryRun)
        {
            var secretPermissionsCode = await transferOperations.EnforceSecretPathPermissionsAsync(
                volume,
                manifestEntries,
                options.NoSecrets,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (secretPermissionsCode != 0)
            {
                return secretPermissionsCode;
            }
        }

        foreach (var additionalPath in additionalImportPaths)
        {
            var copyCode = await pathOperations.ImportAdditionalPathAsync(
                volume,
                additionalPath,
                options.NoExcludes,
                options.DryRun,
                options.Verbose,
                cancellationToken).ConfigureAwait(false);
            if (copyCode != 0)
            {
                return copyCode;
            }
        }

        var environmentCode = await environmentOperations.ImportEnvironmentVariablesAsync(
            volume,
            workspace,
            explicitConfigPath,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (environmentCode != 0)
        {
            return environmentCode;
        }

        var overrideCode = await transferOperations.ApplyImportOverridesAsync(
            volume,
            manifestEntries,
            options.NoSecrets,
            options.DryRun,
            options.Verbose,
            cancellationToken).ConfigureAwait(false);
        if (overrideCode != 0)
        {
            return overrideCode;
        }

        await stdout.WriteLineAsync($"Imported data into volume {volume}").ConfigureAwait(false);
        return 0;
    }

    private static string ResolveDockerContextName()
    {
        var explicitContext = Environment.GetEnvironmentVariable("DOCKER_CONTEXT");
        if (!string.IsNullOrWhiteSpace(explicitContext))
        {
            return explicitContext;
        }

        return "default";
    }
}
