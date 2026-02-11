using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiRuntimeSessionCommandHandler
{
    private readonly SessionCommandRuntime sessionRuntime;

    public CaiRuntimeSessionCommandHandler(SessionCommandRuntime runtime)
        => sessionRuntime = runtime ?? throw new ArgumentNullException(nameof(runtime));

    public Task<int> RunRunAsync(RunCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunRunAsync(options, cancellationToken);

    public Task<int> RunShellAsync(ShellCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunShellAsync(options, cancellationToken);

    public Task<int> RunExecAsync(ExecCommandOptions options, CancellationToken cancellationToken)
        => sessionRuntime.RunExecAsync(options, cancellationToken);
}
