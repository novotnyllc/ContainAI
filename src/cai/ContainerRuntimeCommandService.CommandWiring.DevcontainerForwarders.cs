using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private Task<int> RunSystemDevcontainerInstallCoreAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
        => devcontainerRuntime.RunInstallAsync(options, cancellationToken);

    private Task<int> RunSystemDevcontainerInitCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunInitAsync(cancellationToken);

    private Task<int> RunSystemDevcontainerStartCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunStartAsync(cancellationToken);

    private Task<int> RunSystemDevcontainerVerifySysboxCoreAsync(CancellationToken cancellationToken)
        => devcontainerRuntime.RunVerifySysboxAsync(cancellationToken);
}
