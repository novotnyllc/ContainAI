using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistOperations
{
    Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentAllowlistOperations : IImportEnvironmentAllowlistOperations
{
    private readonly TextWriter stdout;
    private readonly IImportEnvironmentAllowlistParser allowlistParser;
    private readonly IImportEnvironmentAllowlistKeyValidator keyValidator;

    public ImportEnvironmentAllowlistOperations(TextWriter standardOutput, TextWriter standardError)
        : this(
            standardOutput,
            standardError,
            new ImportEnvironmentAllowlistParser(standardError),
            new ImportEnvironmentAllowlistKeyValidator(standardError))
    {
    }

    internal ImportEnvironmentAllowlistOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        IImportEnvironmentAllowlistParser importEnvironmentAllowlistParser,
        IImportEnvironmentAllowlistKeyValidator importEnvironmentAllowlistKeyValidator)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        _ = standardError ?? throw new ArgumentNullException(nameof(standardError));
        allowlistParser = importEnvironmentAllowlistParser ?? throw new ArgumentNullException(nameof(importEnvironmentAllowlistParser));
        keyValidator = importEnvironmentAllowlistKeyValidator ?? throw new ArgumentNullException(nameof(importEnvironmentAllowlistKeyValidator));
    }

    public async Task<List<string>> ResolveValidatedImportKeysAsync(
        JsonElement envSection,
        bool verbose,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var importKeys = await allowlistParser.ParseImportKeysAsync(envSection).ConfigureAwait(false);
        var dedupedImportKeys = ImportEnvironmentAllowlistDeduplicator.Deduplicate(importKeys);

        if (dedupedImportKeys.Count == 0)
        {
            if (verbose)
            {
                await stdout.WriteLineAsync("[INFO] Empty env allowlist, skipping env import").ConfigureAwait(false);
            }

            return [];
        }

        return await keyValidator.ValidateAsync(dedupedImportKeys).ConfigureAwait(false);
    }
}
