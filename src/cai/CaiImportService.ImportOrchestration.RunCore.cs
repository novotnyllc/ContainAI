using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportOrchestrationOperations
{
    private async Task<int> RunImportCoreAsync(ImportCommandOptions options, CancellationToken cancellationToken)
    {
        var runContext = await runContextResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        if (!runContext.Success)
        {
            await stderr.WriteLineAsync(runContext.Error!).ConfigureAwait(false);
            return 1;
        }

        var context = runContext.Value!;

        await stdout.WriteLineAsync($"Using data volume: {context.Volume}").ConfigureAwait(false);
        if (options.DryRun)
        {
            await stdout.WriteLineAsync($"Dry-run context: {ResolveDockerContextName()}").ConfigureAwait(false);
        }

        if (!options.DryRun)
        {
            var ensureVolume = await DockerCaptureAsync(["volume", "create", context.Volume], cancellationToken).ConfigureAwait(false);
            if (ensureVolume.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureVolume.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        ManifestEntry[] manifestEntries;
        try
        {
            manifestEntries = manifestEntryLoader.LoadManifestEntries();
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

        return File.Exists(context.SourcePath)
            ? await archiveHandler.HandleArchiveImportAsync(options, context.SourcePath, context.Volume, context.ExcludePriv, manifestEntries, cancellationToken).ConfigureAwait(false)
            : await directoryHandler.HandleDirectoryImportAsync(
                options,
                context.Workspace,
                context.ExplicitConfigPath,
                context.SourcePath,
                context.Volume,
                context.ExcludePriv,
                manifestEntries,
                cancellationToken).ConfigureAwait(false);
    }
}
