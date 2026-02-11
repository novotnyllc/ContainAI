using System.Text.Json;

namespace ContainAI.Cli.Host;

internal readonly record struct ImportEnvironmentConfigLoadResult(
    bool Success,
    bool ShouldSkip,
    int ExitCode,
    JsonDocument? Document,
    JsonElement Section)
{
    public static ImportEnvironmentConfigLoadResult FromSuccess(JsonDocument document, JsonElement section)
        => new(true, false, 0, document, section);

    public static ImportEnvironmentConfigLoadResult FromSkip()
        => new(false, true, 0, null, default);

    public static ImportEnvironmentConfigLoadResult FromFailure(int exitCode)
        => new(false, false, exitCode, null, default);
}
