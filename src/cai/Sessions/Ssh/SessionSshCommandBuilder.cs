namespace ContainAI.Cli.Host;

internal interface ISessionSshCommandBuilder
{
    List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty);

    string BuildDetachedRemoteCommand(IReadOnlyList<string> commandArgs);

    string BuildForegroundRemoteCommand(IReadOnlyList<string> commandArgs, bool loginShell);
}

internal sealed partial class SessionSshCommandBuilder : ISessionSshCommandBuilder
{
    public List<string> BuildSshArguments(SessionCommandOptions options, string sshPort, string remoteCommand, bool forceTty)
    {
        var args = new List<string>
        {
            "-o", $"HostName={SessionRuntimeConstants.SshHost}",
            "-o", $"Port={sshPort}",
            "-o", "User=agent",
            "-o", $"IdentityFile={SessionRuntimeInfrastructure.ResolveSshPrivateKeyPath()}",
            "-o", "IdentitiesOnly=yes",
            "-o", $"UserKnownHostsFile={SessionRuntimeInfrastructure.ResolveKnownHostsFilePath()}",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PreferredAuthentications=publickey",
            "-o", "GSSAPIAuthentication=no",
            "-o", "PasswordAuthentication=no",
            "-o", "AddressFamily=inet",
            "-o", "ConnectTimeout=10",
        };

        if (options.Quiet)
        {
            args.Add("-q");
        }

        if (options.Verbose)
        {
            args.Add("-v");
        }

        if (forceTty)
        {
            args.Add("-tt");
        }

        args.Add(SessionRuntimeConstants.SshHost);
        args.Add(remoteCommand);
        return args;
    }

}
