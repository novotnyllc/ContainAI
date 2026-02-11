namespace ContainAI.Cli.Host.RuntimeSupport;

internal static partial class CaiRuntimePathResolutionHelpers
{
    internal static async Task<string> ResolveChannelAsync(IReadOnlyList<string> configFileNames, CancellationToken cancellationToken)
    {
        var envChannel = Environment.GetEnvironmentVariable("CAI_CHANNEL")
                         ?? Environment.GetEnvironmentVariable("CONTAINAI_CHANNEL");
        if (string.Equals(envChannel, "nightly", StringComparison.OrdinalIgnoreCase))
        {
            return "nightly";
        }

        if (string.Equals(envChannel, "stable", StringComparison.OrdinalIgnoreCase))
        {
            return "stable";
        }

        var configPath = CaiRuntimeConfigPathHelpers.ResolveUserConfigPath(configFileNames);
        if (!File.Exists(configPath))
        {
            return "stable";
        }

        var result = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "image.channel"), cancellationToken)
            .ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return "stable";
        }

        return string.Equals(result.StandardOutput.Trim(), "nightly", StringComparison.OrdinalIgnoreCase)
            ? "nightly"
            : "stable";
    }
}
