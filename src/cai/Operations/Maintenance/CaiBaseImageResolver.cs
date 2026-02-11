using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiBaseImageResolver
{
    Task<string> ResolveBaseImageAsync(CancellationToken cancellationToken);
}

internal sealed class CaiBaseImageResolver : ICaiBaseImageResolver
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    public async Task<string> ResolveBaseImageAsync(CancellationToken cancellationToken)
    {
        var channel = await CaiRuntimePathResolutionHelpers.ResolveChannelAsync(ConfigFileNames, cancellationToken).ConfigureAwait(false);
        return string.Equals(channel, "nightly", StringComparison.Ordinal)
            ? "ghcr.io/novotnyllc/containai:nightly"
            : "ghcr.io/novotnyllc/containai:latest";
    }
}
