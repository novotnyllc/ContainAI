using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentAllowlistOperations
{
    Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken);
}

internal sealed partial class ImportEnvironmentAllowlistOperations : CaiRuntimeSupport
    , IImportEnvironmentAllowlistOperations
{
    public ImportEnvironmentAllowlistOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var importKeys = await ResolveImportKeysAsync(envSection).ConfigureAwait(false);
        var dedupedImportKeys = DeduplicateImportKeys(importKeys);

        if (dedupedImportKeys.Count == 0)
        {
            if (verbose)
            {
                await stdout.WriteLineAsync("[INFO] Empty env allowlist, skipping env import").ConfigureAwait(false);
            }

            return [];
        }

        return await ValidateImportKeysAsync(dedupedImportKeys).ConfigureAwait(false);
    }
}
