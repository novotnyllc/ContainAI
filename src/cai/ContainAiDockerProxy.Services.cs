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

internal sealed class DockerProxyCommandExecutor : IDockerProxyCommandExecutor
{
    private readonly IDockerProxyProcessRunner processRunner;

    public DockerProxyCommandExecutor(IDockerProxyProcessRunner processRunner) => this.processRunner = processRunner;

    public async Task<int> RunInteractiveAsync(IReadOnlyList<string> args, TextWriter stderr, CancellationToken cancellationToken)
    {
        try
        {
            return await processRunner.RunInteractiveAsync(args, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    public async Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        try
        {
            return await processRunner.RunCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (NotSupportedException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
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
