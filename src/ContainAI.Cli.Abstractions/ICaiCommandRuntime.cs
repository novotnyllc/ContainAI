namespace ContainAI.Cli.Abstractions;

public interface ICaiCommandRuntime
{
    Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken);

    Task<int> RunNativeAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunLegacyAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<int> RunAcpProxyAsync(string agent, CancellationToken cancellationToken);
}
