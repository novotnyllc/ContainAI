namespace ContainAI.Cli.Host.Devcontainer;

internal sealed class DevcontainerSshdStartupService(
    IDevcontainerProcessHelpers processHelpers,
    TextWriter standardOutput,
    TextWriter standardError,
    Func<string, string?> environmentVariableReader) : IDevcontainerSshdStartupService
{
    public async Task<int> StartSshdAsync(CancellationToken cancellationToken)
    {
        if (!await processHelpers.CommandExistsAsync("sshd", cancellationToken).ConfigureAwait(false))
        {
            await standardError.WriteLineAsync("Warning: sshd not installed").ConfigureAwait(false);
            return 0;
        }

        var sshPort = environmentVariableReader("CONTAINAI_SSH_PORT") ?? "2322";
        if (await processHelpers.IsSshdRunningFromPidFileAsync(DevcontainerFeaturePaths.DefaultSshPidFile, cancellationToken).ConfigureAwait(false))
        {
            await standardOutput.WriteLineAsync($"[OK] sshd already running on port {sshPort} (validated via pidfile)").ConfigureAwait(false);
            return 0;
        }

        if (processHelpers.IsPortInUse(sshPort))
        {
            await standardOutput.WriteLineAsync($"[OK] sshd appears to be running on port {sshPort} (port in use)").ConfigureAwait(false);
            return 0;
        }

        if (File.Exists(DevcontainerFeaturePaths.DefaultSshPidFile))
        {
            await processHelpers.RunAsRootAsync("rm", ["-f", DevcontainerFeaturePaths.DefaultSshPidFile], cancellationToken).ConfigureAwait(false);
        }

        await processHelpers.RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
        await processHelpers.RunAsRootAsync("chmod", ["755", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);

        if (!File.Exists("/etc/ssh/ssh_host_rsa_key"))
        {
            await processHelpers.RunAsRootAsync("ssh-keygen", ["-A"], cancellationToken).ConfigureAwait(false);
        }

        await processHelpers.RunAsRootAsync("/usr/sbin/sshd", ["-p", sshPort, "-o", $"PidFile={DevcontainerFeaturePaths.DefaultSshPidFile}"], cancellationToken).ConfigureAwait(false);
        await standardOutput.WriteLineAsync($"[OK] sshd started on port {sshPort}").ConfigureAwait(false);
        return 0;
    }
}
