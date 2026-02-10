namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

internal interface IContainerRuntimePrivilegedCommandService
{
    Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments);

    Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimePrivilegedCommandService : IContainerRuntimePrivilegedCommandService
{
    private readonly IContainerRuntimeProcessExecutor processExecutor;

    public ContainerRuntimePrivilegedCommandService(IContainerRuntimeProcessExecutor processExecutor)
        => this.processExecutor = processExecutor ?? throw new ArgumentNullException(nameof(processExecutor));

    public Task RunAsRootAsync(string executable, IReadOnlyList<string> arguments)
        => RunAsRootCaptureAsync(executable, arguments, null, CancellationToken.None);

    public async Task<ProcessCaptureResult> RunAsRootCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? standardInput,
        CancellationToken cancellationToken)
    {
        if (IsRunningAsRoot())
        {
            var direct = await processExecutor
                .RunCaptureAsync(executable, arguments, null, cancellationToken, standardInput)
                .ConfigureAwait(false);
            if (direct.ExitCode != 0)
            {
                throw new InvalidOperationException($"Command failed: {executable} {string.Join(' ', arguments)}: {direct.StandardError.Trim()}");
            }

            return direct;
        }

        var sudoArguments = new List<string>(capacity: arguments.Count + 2)
        {
            "-n",
            executable,
        };

        foreach (var argument in arguments)
        {
            sudoArguments.Add(argument);
        }

        var sudo = await processExecutor
            .RunCaptureAsync("sudo", sudoArguments, null, cancellationToken, standardInput)
            .ConfigureAwait(false);
        if (sudo.ExitCode != 0)
        {
            throw new InvalidOperationException($"sudo command failed for {executable}: {sudo.StandardError.Trim()}");
        }

        return sudo;
    }

    private static bool IsRunningAsRoot()
    {
        try
        {
            return string.Equals(Environment.UserName, "root", StringComparison.Ordinal);
        }
        catch (InvalidOperationException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }
}
