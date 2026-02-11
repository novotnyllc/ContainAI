using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal readonly record struct ImportEnvironmentSectionLoadResult(
    bool Success,
    int ExitCode,
    JsonDocument? Document,
    JsonElement Section)
{
    public static ImportEnvironmentSectionLoadResult FromSuccess(JsonDocument document, JsonElement section)
        => new(true, 0, document, section);

    public static ImportEnvironmentSectionLoadResult FromFailure(int exitCode)
        => new(false, exitCode, null, default);
}
