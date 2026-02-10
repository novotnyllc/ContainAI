namespace ContainAI.Cli.Host;

internal interface ISessionSshPortReadinessService
{
    Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken);
}

internal sealed class SessionSshPortReadinessService : ISessionSshPortReadinessService
{
    public async Task<bool> WaitForSshPortAsync(string sshPort, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 30; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var scan = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "ssh-keyscan",
                ["-p", sshPort, "-T", "2", SessionRuntimeConstants.SshHost],
                cancellationToken).ConfigureAwait(false);
            if (scan.ExitCode == 0)
            {
                return true;
            }

            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }

        return false;
    }
}
