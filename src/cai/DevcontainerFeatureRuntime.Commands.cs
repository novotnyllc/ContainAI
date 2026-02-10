using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    public async Task<int> RunDevcontainerAsync(CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        await stderr.WriteLineAsync("Usage: cai system devcontainer <install|init|start|verify-sysbox>").ConfigureAwait(false);
        return 1;
    }

    public Task<int> RunInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return installWorkflow.RunInstallAsync(options, cancellationToken);
    }

    public Task<int> RunInitAsync(CancellationToken cancellationToken)
        => initWorkflow.RunInitAsync(cancellationToken);

    public Task<int> RunStartAsync(CancellationToken cancellationToken)
        => startWorkflow.RunStartAsync(cancellationToken);

    public Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken)
        => startWorkflow.RunVerifySysboxAsync(cancellationToken);
}
