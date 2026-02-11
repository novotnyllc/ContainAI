namespace ContainAI.Cli.Host;

internal interface IDevcontainerFeatureInstallSummaryWriter
{
    Task WriteAsync(FeatureConfig settings);
}

internal sealed class DevcontainerFeatureInstallSummaryWriter(
    TextWriter stdout) : IDevcontainerFeatureInstallSummaryWriter
{
    public async Task WriteAsync(FeatureConfig settings)
    {
        await stdout.WriteLineAsync("ContainAI feature installed successfully").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Data volume: {settings.DataVolume}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Credentials: {settings.EnableCredentials}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  SSH: {settings.EnableSsh}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"  Docker: {settings.InstallDocker}").ConfigureAwait(false);
    }
}
