using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Ssh;

namespace ContainAI.Cli.Host.Sessions.Execution.Ssh;

internal sealed class SessionSshExecutionService : ISessionSshExecutionService
{
    private readonly ISessionSshCommandBuilder sshCommandBuilder;
    private readonly TextWriter standardError;

    public SessionSshExecutionService(
        ISessionSshCommandBuilder sessionSshCommandBuilder,
        TextWriter standardError)
    {
        sshCommandBuilder = sessionSshCommandBuilder ?? throw new ArgumentNullException(nameof(sessionSshCommandBuilder));
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> RunInteractiveAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentException.ThrowIfNullOrWhiteSpace(sshPort);
        ArgumentException.ThrowIfNullOrWhiteSpace(remoteCommand);

        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeProcessHelpers
            .RunProcessInteractiveAsync("ssh", args, standardError, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task<ProcessResult> RunCaptureAsync(
        SessionCommandOptions options,
        string sshPort,
        string remoteCommand,
        bool forceTty,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentException.ThrowIfNullOrWhiteSpace(sshPort);
        ArgumentException.ThrowIfNullOrWhiteSpace(remoteCommand);

        var args = sshCommandBuilder.BuildSshArguments(options, sshPort, remoteCommand, forceTty);
        return await SessionRuntimeProcessHelpers.RunProcessCaptureAsync("ssh", args, cancellationToken).ConfigureAwait(false);
    }
}
