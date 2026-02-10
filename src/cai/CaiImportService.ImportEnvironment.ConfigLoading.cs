using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportEnvironmentOperations
{
    private static string ResolveEnvironmentConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : ResolveConfigPath(workspace);

    private async Task<EnvironmentSectionParseResult> TryLoadEnvironmentSectionAsync(string configPath, CancellationToken cancellationToken)
    {
        var configResult = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (configResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(configResult.StandardError))
            {
                await stderr.WriteLineAsync(configResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return EnvironmentSectionParseResult.FromFailure(1);
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
            return EnvironmentSectionParseResult.FromFailure(0);
        }

        return EnvironmentSectionParseResult.FromSuccess(configDocument, envSection);
    }

    private readonly record struct EnvironmentSectionParseResult(
        bool Success,
        int ExitCode,
        JsonDocument? Document,
        JsonElement Section)
    {
        public static EnvironmentSectionParseResult FromSuccess(JsonDocument document, JsonElement section)
            => new(true, 0, document, section);

        public static EnvironmentSectionParseResult FromFailure(int exitCode)
            => new(false, exitCode, null, default);
    }
}
