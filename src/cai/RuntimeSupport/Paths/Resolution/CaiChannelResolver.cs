using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host.RuntimeSupport.Paths.Resolution;

internal static class CaiChannelResolver
{
    private const string StableChannel = "stable";
    private const string NightlyChannel = "nightly";

    public static async Task<string> ResolveChannelAsync(IReadOnlyList<string> configFileNames, CancellationToken cancellationToken)
    {
        var envChannel = System.Environment.GetEnvironmentVariable("CAI_CHANNEL")
            ?? System.Environment.GetEnvironmentVariable("CONTAINAI_CHANNEL");

        if (string.Equals(envChannel, NightlyChannel, StringComparison.OrdinalIgnoreCase))
        {
            return NightlyChannel;
        }

        if (string.Equals(envChannel, StableChannel, StringComparison.OrdinalIgnoreCase))
        {
            return StableChannel;
        }

        var configPath = CaiRuntimeConfigLocator.ResolveUserConfigPath(configFileNames);
        if (!File.Exists(configPath))
        {
            return StableChannel;
        }

        var result = await CaiRuntimeParseAndTimeHelpers
            .RunTomlAsync(() => TomlCommandProcessor.GetKey(configPath, "image.channel"), cancellationToken)
            .ConfigureAwait(false);

        if (result.ExitCode != 0)
        {
            return StableChannel;
        }

        return string.Equals(result.StandardOutput.Trim(), NightlyChannel, StringComparison.OrdinalIgnoreCase)
            ? NightlyChannel
            : StableChannel;
    }
}
