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

internal sealed partial class CaiImportEnvironmentOperations : CaiRuntimeSupport
    , IImportEnvironmentOperations
{
    internal const string EnvTargetSymlinkGuardMessage = ".env target is symlink";

    private readonly IImportEnvironmentValueOperations environmentValueOperations;

    public CaiImportEnvironmentOperations(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ImportEnvironmentValueOperations(standardOutput, standardError))
    {
    }

    internal CaiImportEnvironmentOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentValueOperations importEnvironmentValueOperations)
        : base(standardOutput, standardError)
        => environmentValueOperations = importEnvironmentValueOperations ?? throw new ArgumentNullException(nameof(importEnvironmentValueOperations));
}
