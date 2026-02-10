namespace ContainAI.Cli.Host;

internal sealed partial class CaiDiagnosticsAndSetupOperations
{
    public async Task<int> RunVersionAsync(bool json, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        if (json)
        {
            await stdout.WriteLineAsync($"{{\"version\":\"{versionInfo.Version}\",\"install_type\":\"{installType}\",\"install_dir\":\"{EscapeJson(versionInfo.InstallDir)}\"}}").ConfigureAwait(false);
            return 0;
        }

        await stdout.WriteLineAsync(versionInfo.Version).ConfigureAwait(false);
        return 0;
    }
}
