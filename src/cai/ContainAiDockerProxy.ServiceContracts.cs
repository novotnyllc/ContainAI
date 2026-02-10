namespace ContainAI.Cli.Host;

internal interface IContainAiDockerProxyService
{
    Task<int> RunAsync(IReadOnlyList<string> args, TextWriter stdout, TextWriter stderr, CancellationToken cancellationToken);
}

internal interface IDockerProxyProcessRunner
{
    Task<int> RunInteractiveAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);

    Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);
}

internal interface IDockerProxyCommandExecutor
{
    Task<int> RunInteractiveAsync(IReadOnlyList<string> args, TextWriter stderr, CancellationToken cancellationToken);

    Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken);
}

internal interface IContainAiSystemEnvironment
{
    string? GetEnvironmentVariable(string variableName);

    string ResolveHomeDirectory();

    bool IsPortInUse(int port);
}

internal interface IUtcClock
{
    DateTime UtcNow { get; }
}
