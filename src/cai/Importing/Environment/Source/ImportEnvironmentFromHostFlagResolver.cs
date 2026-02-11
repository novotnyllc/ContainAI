using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentFromHostFlagResolver
{
    Task<bool> ResolveAsync(JsonElement envSection, CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentFromHostFlagResolver : IImportEnvironmentFromHostFlagResolver
{
    private readonly TextWriter stderr;

    public ImportEnvironmentFromHostFlagResolver(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<bool> ResolveAsync(JsonElement envSection, CancellationToken cancellationToken)
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
