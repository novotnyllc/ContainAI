namespace ContainAI.Cli.Abstractions;

public interface ICommandRuntimeService
{
    Task<int> RunProcessAsync(ProcessExecutionSpec spec, CancellationToken cancellationToken);

    Task<int> RunDockerAsync(DockerExecutionSpec spec, CancellationToken cancellationToken);
}
