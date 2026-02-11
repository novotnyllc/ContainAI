using System.Text.Json;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureInstallWorkflow : IDevcontainerFeatureInstallWorkflow
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerProcessHelpers processHelpers;
    private readonly IDevcontainerUserEnvironmentSetup userEnvironmentSetup;
    private readonly IDevcontainerFeatureSettingsFactory settingsFactory;

    public DevcontainerFeatureInstallWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerFeatureSettingsFactory settingsFactory)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        this.userEnvironmentSetup = userEnvironmentSetup ?? throw new ArgumentNullException(nameof(userEnvironmentSetup));
        this.settingsFactory = settingsFactory ?? throw new ArgumentNullException(nameof(settingsFactory));
    }

    public async Task<int> RunInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var featureDirectory = options.FeatureDir;

        if (!settingsFactory.TryCreateFeatureConfig(out var settings, out var featureConfigError))
        {
            await stderr.WriteLineAsync(featureConfigError).ConfigureAwait(false);
            return 1;
        }

        if (!await processHelpers.CommandExistsAsync("apt-get", cancellationToken).ConfigureAwait(false))
        {
            await stderr.WriteLineAsync("ContainAI feature requires Debian/Ubuntu image with apt-get.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("ContainAI: Installing feature...").ConfigureAwait(false);
        Directory.CreateDirectory("/usr/local/share/containai");
        Directory.CreateDirectory("/usr/local/lib/containai");

        var configJson = JsonSerializer.Serialize(
            settings,
            DevcontainerFeatureJsonContext.Default.FeatureConfig);
        await File.WriteAllTextAsync(DevcontainerFeaturePaths.DefaultConfigPath, configJson + Environment.NewLine, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync("  Configuration saved").ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(featureDirectory))
        {
            var sourceLinkSpec = Path.Combine(featureDirectory, "link-spec.json");
            if (File.Exists(sourceLinkSpec))
            {
                File.Copy(sourceLinkSpec, DevcontainerFeaturePaths.DefaultLinkSpecPath, overwrite: true);
                await stdout.WriteLineAsync("  Installed: link-spec.json").ConfigureAwait(false);
            }
            else
            {
                await stdout.WriteLineAsync("  Note: link-spec.json not bundled - symlinks will be skipped").ConfigureAwait(false);
            }
        }

        await processHelpers.RunAsRootAsync("apt-get", ["update", "-qq"], cancellationToken).ConfigureAwait(false);
        await InstallOptionalFeaturesAsync(settings, cancellationToken).ConfigureAwait(false);

        await processHelpers.RunAsRootAsync("apt-get", ["clean"], cancellationToken).ConfigureAwait(false);
        await processHelpers.RunAsRootAsync("sh", ["-c", "rm -rf /var/lib/apt/lists/*"], cancellationToken).ConfigureAwait(false);

        await WriteInstallSummaryAsync(settings).ConfigureAwait(false);
        return 0;
    }

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
