using ContainAI.Cli.Host.Importing.Environment;

namespace ContainAI.Cli.Host;

internal interface IImportEnvironmentOperations
{
    Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportEnvironmentOperations : IImportEnvironmentOperations
{
    internal const string EnvTargetSymlinkGuardMessage = ".env target is symlink";

    private readonly IImportEnvironmentValueOperations environmentValueOperations;
    private readonly ImportEnvironmentConfigLoadCoordinator configLoadCoordinator;
    private readonly ImportEnvironmentSectionValidator sectionValidator;
    private readonly ImportEnvironmentMergePersistCoordinator mergePersistCoordinator;

    public CaiImportEnvironmentOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportEnvironmentValueOperations(standardOutput, standardError),
            new ImportEnvironmentSectionLoader(standardError))
    {
    }

    internal CaiImportEnvironmentOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentValueOperations importEnvironmentValueOperations,
        IImportEnvironmentSectionLoader importEnvironmentSectionLoader)
    {
        var output = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        var error = standardError ?? throw new ArgumentNullException(nameof(standardError));
        environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));
        var sectionLoader = importEnvironmentSectionLoader ?? throw new ArgumentNullException(nameof(importEnvironmentSectionLoader));

        var dryRunReporter = new ImportEnvironmentDryRunReporter(output);
        configLoadCoordinator = new ImportEnvironmentConfigLoadCoordinator(sectionLoader);
        sectionValidator = new ImportEnvironmentSectionValidator(error);
        mergePersistCoordinator = new ImportEnvironmentMergePersistCoordinator(
            environmentValueOperations,
            dryRunReporter);
    }

    public async Task<int> ImportEnvironmentVariablesAsync(
        string volume,
        string workspace,
        string? explicitConfigPath,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var loadResult = await configLoadCoordinator
            .LoadAsync(workspace, explicitConfigPath, cancellationToken)
            .ConfigureAwait(false);
        if (loadResult.ShouldSkip)
        {
            return 0;
        }

        if (!loadResult.Success)
        {
            return loadResult.ExitCode;
        }

        using var configDocument = loadResult.Document!;
        var envSection = loadResult.Section;
        var sectionIsValid = await sectionValidator
            .ValidateAsync(envSection, cancellationToken)
            .ConfigureAwait(false);
        if (!sectionIsValid)
        {
            return 0;
        }

        var validatedKeys = await environmentValueOperations
            .ResolveValidatedImportKeysAsync(envSection, verbose, cancellationToken)
            .ConfigureAwait(false);

        if (validatedKeys.Count == 0)
        {
            return 0;
        }

        return await mergePersistCoordinator
            .MergeAndPersistAsync(
                volume,
                workspace,
                envSection,
                validatedKeys,
                dryRun,
                cancellationToken)
            .ConfigureAwait(false);
    }
}
