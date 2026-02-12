using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed class ImportEnvironmentSectionLoader : IImportEnvironmentSectionLoader
{
    private readonly TextWriter stderr;

    public ImportEnvironmentSectionLoader(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<ImportEnvironmentSectionLoadResult> LoadAsync(string configPath, CancellationToken cancellationToken)
    {
        var configResult = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken)
            .ConfigureAwait(false);

        if (configResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(configResult.StandardError))
            {
                await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return ImportEnvironmentSectionLoadResult.FromFailure(1);
        }

        if (!string.IsNullOrWhiteSpace(configResult.StandardError))
        {
            await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
        }

        var configDocument = JsonDocument.Parse(configResult.StandardOutput);
        if (configDocument.RootElement.ValueKind != JsonValueKind.Object ||
            !configDocument.RootElement.TryGetProperty("env", out var envSection))
        {
            configDocument.Dispose();
            return ImportEnvironmentSectionLoadResult.FromFailure(0);
        }

        return ImportEnvironmentSectionLoadResult.FromSuccess(configDocument, envSection);
    }
}
