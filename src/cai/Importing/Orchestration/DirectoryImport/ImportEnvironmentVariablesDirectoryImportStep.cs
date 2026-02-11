namespace ContainAI.Cli.Host;

internal sealed class ImportEnvironmentVariablesDirectoryImportStep : IDirectoryImportStep
{
    private readonly IImportEnvironmentOperations environmentOperations;

    public ImportEnvironmentVariablesDirectoryImportStep(IImportEnvironmentOperations importEnvironmentOperations)
        => environmentOperations = importEnvironmentOperations ?? throw new ArgumentNullException(nameof(importEnvironmentOperations));

    public Task<int> ExecuteAsync(DirectoryImportContext context, CancellationToken cancellationToken)
        => environmentOperations.ImportEnvironmentVariablesAsync(
            context.Volume,
            context.Workspace,
            context.ExplicitConfigPath,
            context.Options.DryRun,
            context.Options.Verbose,
            cancellationToken);
}
