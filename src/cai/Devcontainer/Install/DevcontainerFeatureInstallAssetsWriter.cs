using System.Text.Json;

namespace ContainAI.Cli.Host.Devcontainer.Install;

internal interface IDevcontainerFeatureInstallAssetsWriter
{
    Task WriteAsync(FeatureConfig settings, string? featureDirectory, CancellationToken cancellationToken);
}

internal sealed class DevcontainerFeatureInstallAssetsWriter(
    TextWriter stdout) : IDevcontainerFeatureInstallAssetsWriter
{
    public async Task WriteAsync(FeatureConfig settings, string? featureDirectory, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory("/usr/local/share/containai");
        Directory.CreateDirectory("/usr/local/lib/containai");

        var configJson = JsonSerializer.Serialize(
            settings,
            DevcontainerFeatureJsonContext.Default.FeatureConfig);
        await File.WriteAllTextAsync(
            DevcontainerFeaturePaths.DefaultConfigPath,
            configJson + Environment.NewLine,
            cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync("  Configuration saved").ConfigureAwait(false);

        if (string.IsNullOrWhiteSpace(featureDirectory))
        {
            return;
        }

        var sourceLinkSpec = Path.Combine(featureDirectory, "link-spec.json");
        if (File.Exists(sourceLinkSpec))
        {
            File.Copy(sourceLinkSpec, DevcontainerFeaturePaths.DefaultLinkSpecPath, overwrite: true);
            await stdout.WriteLineAsync("  Installed: link-spec.json").ConfigureAwait(false);
            return;
        }

        await stdout.WriteLineAsync("  Note: link-spec.json not bundled - symlinks will be skipped").ConfigureAwait(false);
    }
}
