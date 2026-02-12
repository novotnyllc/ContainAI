namespace ContainAI.Cli.Host.Devcontainer.Install;

internal interface IDevcontainerFeatureOptionalInstaller
{
    Task InstallAsync(FeatureConfig settings, CancellationToken cancellationToken);
}

internal sealed class DevcontainerFeatureOptionalInstaller(
    TextWriter stdout,
    IDevcontainerProcessHelpers processHelpers,
    IDevcontainerUserEnvironmentSetup userEnvironmentSetup) : IDevcontainerFeatureOptionalInstaller
{
    public async Task InstallAsync(FeatureConfig settings, CancellationToken cancellationToken)
    {
        await processHelpers.RunAsRootAsync("apt-get", ["update", "-qq"], cancellationToken).ConfigureAwait(false);

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

        await processHelpers.RunAsRootAsync("apt-get", ["clean"], cancellationToken).ConfigureAwait(false);
        await processHelpers.RunAsRootAsync("sh", ["-c", "rm -rf /var/lib/apt/lists/*"], cancellationToken).ConfigureAwait(false);
    }
}
