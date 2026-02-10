namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureInstallWorkflow
{
    private async Task InstallOptionalFeaturesAsync(FeatureConfig settings, CancellationToken cancellationToken)
    {
        if (settings.EnableSsh)
        {
            await processHelpers.RunAsRootAsync("apt-get", ["install", "-y", "-qq", "openssh-server"], cancellationToken).ConfigureAwait(false);
            await processHelpers.RunAsRootAsync("mkdir", ["-p", "/var/run/sshd"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: openssh-server").ConfigureAwait(false);
        }

        if (settings.InstallDocker)
        {
            await processHelpers.RunAsRootAsync("apt-get", ["install", "-y", "-qq", "curl", "ca-certificates"], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: curl, ca-certificates").ConfigureAwait(false);
            await processHelpers.RunAsRootAsync("sh", ["-c", "curl -fsSL https://get.docker.com | sh"], cancellationToken).ConfigureAwait(false);
            await userEnvironmentSetup.AddUserToDockerGroupIfPresentAsync("vscode", cancellationToken).ConfigureAwait(false);
            await userEnvironmentSetup.AddUserToDockerGroupIfPresentAsync("node", cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync("    Installed: docker (DinD starts via postStartCommand)").ConfigureAwait(false);
        }
    }

    private async Task WriteInstallSummaryAsync(FeatureConfig settings)
    {
        await stdout.WriteLineAsync("ContainAI feature installed successfully").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Data volume: {settings.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Credentials: {settings.EnableCredentials}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  SSH: {settings.EnableSsh}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Docker: {settings.InstallDocker}").ConfigureAwait(false);
    }
}
