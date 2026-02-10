using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed partial class ImportEnvironmentSourceOperations
{
    public async Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (envSection.TryGetProperty("from_host", out var fromHostElement))
        {
            if (fromHostElement.ValueKind == JsonValueKind.True)
            {
                return true;
            }

            if (fromHostElement.ValueKind != JsonValueKind.False)
            {
                await stderr.WriteLineAsync("[WARN] [env].from_host must be a boolean; using false").ConfigureAwait(false);
            }
        }

        return false;
    }
}
