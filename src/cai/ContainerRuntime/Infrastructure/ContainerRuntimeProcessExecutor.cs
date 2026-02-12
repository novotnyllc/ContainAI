namespace ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

using ContainAI.Cli.Host.ContainerRuntime.Models;

internal sealed class ContainerRuntimeProcessExecutor : IContainerRuntimeProcessExecutor
{
    public async Task<ProcessCaptureResult> RunCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        string? workingDirectory,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        var result = await CliWrapProcessRunner
            .RunCaptureAsync(executable, arguments, cancellationToken, workingDirectory, standardInput)
            .ConfigureAwait(false);

        return new ProcessCaptureResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
