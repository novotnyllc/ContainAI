using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class ImportEnvironmentSectionValidator
{
    private readonly TextWriter stderr;

    public ImportEnvironmentSectionValidator(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<bool> ValidateAsync(JsonElement envSection, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        if (envSection.ValueKind != JsonValueKind.Object)
        {
            await stderr.WriteLineAsync("[WARN] [env] section must be a table; skipping env import").ConfigureAwait(false);
            return false;
        }

        return true;
    }
}
