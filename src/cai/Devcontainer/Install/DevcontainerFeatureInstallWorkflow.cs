using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.Devcontainer;
using ContainAI.Cli.Host.Devcontainer.Configuration;

namespace ContainAI.Cli.Host.Devcontainer.Install;

internal sealed class DevcontainerFeatureInstallWorkflow : IDevcontainerFeatureInstallWorkflow
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerProcessHelpers processHelpers;
    private readonly IDevcontainerFeatureSettingsFactory settingsFactory;
    private readonly IDevcontainerFeatureInstallAssetsWriter assetsWriter;
    private readonly IDevcontainerFeatureOptionalInstaller optionalInstaller;
    private readonly IDevcontainerFeatureInstallSummaryWriter summaryWriter;

    public DevcontainerFeatureInstallWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerUserEnvironmentSetup userEnvironmentSetup,
        IDevcontainerFeatureSettingsFactory settingsFactory)
        : this(
            stdout,
            stderr,
            processHelpers,
            settingsFactory,
            new DevcontainerFeatureInstallAssetsWriter(stdout),
            new DevcontainerFeatureOptionalInstaller(stdout, processHelpers, userEnvironmentSetup),
            new DevcontainerFeatureInstallSummaryWriter(stdout))
    {
    }

    internal DevcontainerFeatureInstallWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerProcessHelpers processHelpers,
        IDevcontainerFeatureSettingsFactory settingsFactory,
        IDevcontainerFeatureInstallAssetsWriter assetsWriter,
        IDevcontainerFeatureOptionalInstaller optionalInstaller,
        IDevcontainerFeatureInstallSummaryWriter summaryWriter)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.processHelpers = processHelpers ?? throw new ArgumentNullException(nameof(processHelpers));
        this.settingsFactory = settingsFactory ?? throw new ArgumentNullException(nameof(settingsFactory));
        this.assetsWriter = assetsWriter ?? throw new ArgumentNullException(nameof(assetsWriter));
        this.optionalInstaller = optionalInstaller ?? throw new ArgumentNullException(nameof(optionalInstaller));
        this.summaryWriter = summaryWriter ?? throw new ArgumentNullException(nameof(summaryWriter));
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
        await assetsWriter.WriteAsync(settings, featureDirectory, cancellationToken).ConfigureAwait(false);
        await optionalInstaller.InstallAsync(settings, cancellationToken).ConfigureAwait(false);
        await summaryWriter.WriteAsync(settings).ConfigureAwait(false);
        return 0;
    }
}
