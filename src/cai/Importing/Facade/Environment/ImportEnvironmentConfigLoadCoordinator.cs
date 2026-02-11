using ContainAI.Cli.Host.Importing.Environment;

namespace ContainAI.Cli.Host;

internal sealed class ImportEnvironmentConfigLoadCoordinator
{
    private readonly IImportEnvironmentSectionLoader sectionLoader;

    public ImportEnvironmentConfigLoadCoordinator(IImportEnvironmentSectionLoader importEnvironmentSectionLoader)
        => sectionLoader = importEnvironmentSectionLoader ?? throw new ArgumentNullException(nameof(importEnvironmentSectionLoader));

    public async Task<ImportEnvironmentConfigLoadResult> LoadAsync(
        string workspace,
        string? explicitConfigPath,
        CancellationToken cancellationToken)
    {
        var configPath = ImportEnvironmentConfigPathResolver.ResolveEnvironmentConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return ImportEnvironmentConfigLoadResult.FromSkip();
        }

        var envSectionResult = await sectionLoader.LoadAsync(configPath, cancellationToken).ConfigureAwait(false);
        if (!envSectionResult.Success)
        {
            return ImportEnvironmentConfigLoadResult.FromFailure(envSectionResult.ExitCode);
        }

        return ImportEnvironmentConfigLoadResult.FromSuccess(envSectionResult.Document!, envSectionResult.Section);
    }
}
