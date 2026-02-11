using System.Text.Json;
using ContainAI.Cli.Host.Importing.Environment.Source;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentSourceOperations
{
    Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken);

    Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken);

    Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentSourceOperations : IImportEnvironmentSourceOperations
{
    private readonly IImportEnvironmentFileVariableResolver fileVariableResolver;
    private readonly IImportEnvironmentFromHostFlagResolver fromHostFlagResolver;
    private readonly IImportEnvironmentHostValueResolver hostValueResolver;
    private readonly IImportEnvironmentVariableMerger variableMerger;

    public ImportEnvironmentSourceOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportEnvironmentFileVariableResolver(standardError),
            new ImportEnvironmentFromHostFlagResolver(standardError),
            new ImportEnvironmentHostValueResolver(standardError),
            new ImportEnvironmentVariableMerger())
    {
    }

    internal ImportEnvironmentSourceOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentFileVariableResolver importEnvironmentFileVariableResolver,
        IImportEnvironmentFromHostFlagResolver importEnvironmentFromHostFlagResolver,
        IImportEnvironmentHostValueResolver importEnvironmentHostValueResolver,
        IImportEnvironmentVariableMerger importEnvironmentVariableMerger)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        fileVariableResolver = importEnvironmentFileVariableResolver ?? throw new ArgumentNullException(nameof(importEnvironmentFileVariableResolver));
        fromHostFlagResolver = importEnvironmentFromHostFlagResolver ?? throw new ArgumentNullException(nameof(importEnvironmentFromHostFlagResolver));
        hostValueResolver = importEnvironmentHostValueResolver ?? throw new ArgumentNullException(nameof(importEnvironmentHostValueResolver));
        variableMerger = importEnvironmentVariableMerger ?? throw new ArgumentNullException(nameof(importEnvironmentVariableMerger));
    }

    public Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken)
        => fileVariableResolver.ResolveAsync(envSection, workspaceRoot, validatedKeys, cancellationToken);

    public Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken)
        => fromHostFlagResolver.ResolveAsync(envSection, cancellationToken);

    public async Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!fromHost)
        {
            return variableMerger.Merge(
                fileVariables,
                new Dictionary<string, string>(StringComparer.Ordinal));
        }

        var hostVariables = await hostValueResolver.ResolveAsync(validatedKeys, cancellationToken).ConfigureAwait(false);
        return variableMerger.Merge(fileVariables, hostVariables);
    }
}
