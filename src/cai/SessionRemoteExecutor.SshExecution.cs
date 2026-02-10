namespace ContainAI.Cli.Host;

internal sealed partial class SessionRemoteExecutor
{
    private async Task<int> RunSshInteractiveAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessInteractiveAsync("ssh", args, stderr, cancellationToken).ConfigureAwait(false);
    }

    private async Task<ProcessResult> RunSshCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeInfrastructure.RunProcessCaptureAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }
}
