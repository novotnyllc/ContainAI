using System.Net.NetworkInformation;

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

internal sealed partial class ContainAiDockerProxyService : IContainAiDockerProxyService
{
    private static readonly HashSet<string> ContainerTargetingSubcommands =
    [
        "exec",
        "inspect",
        "start",
        "stop",
        "rm",
        "logs",
        "restart",
        "kill",
        "pause",
        "unpause",
        "port",
        "stats",
        "top",
    ];

    private readonly ContainAiDockerProxyOptions options;
    private readonly IDockerProxyArgumentParser argumentParser;
    private readonly IDevcontainerFeatureSettingsParser featureSettingsParser;
    private readonly IDockerProxyProcessRunner processRunner;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IUtcClock clock;

    public ContainAiDockerProxyService(
        ContainAiDockerProxyOptions options,
        IDockerProxyArgumentParser argumentParser,
        IDevcontainerFeatureSettingsParser featureSettingsParser,
        IDockerProxyProcessRunner processRunner,
        IContainAiSystemEnvironment environment,
        IUtcClock clock)
    {
        this.options = options;
        this.argumentParser = argumentParser;
        this.featureSettingsParser = featureSettingsParser;
        this.processRunner = processRunner;
        this.environment = environment;
        this.clock = clock;
    }
}

internal sealed class DockerProxyProcessRunner : IDockerProxyProcessRunner
{
    public Task<int> RunInteractiveAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
        => CliWrapProcessRunner.RunInteractiveAsync("docker", args, cancellationToken);

    public async Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        var result = await CliWrapProcessRunner.RunCaptureAsync("docker", args, cancellationToken).ConfigureAwait(false);
        return new DockerProxyProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}

internal sealed class ContainAiSystemEnvironment : IContainAiSystemEnvironment
{
    public string? GetEnvironmentVariable(string variableName) => Environment.GetEnvironmentVariable(variableName);

    public string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        return !string.IsNullOrWhiteSpace(home)
            ? home!
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }

    public bool IsPortInUse(int port)
    {
        try
        {
            return IPGlobalProperties.GetIPGlobalProperties()
                .GetActiveTcpListeners()
                .Any(endpoint => endpoint.Port == port);
        }
        catch (NetworkInformationException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}

internal sealed class SystemUtcClock : IUtcClock
{
    public DateTime UtcNow => DateTime.UtcNow;
}
