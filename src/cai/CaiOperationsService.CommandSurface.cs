using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiOperationsService : CaiRuntimeSupport
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly ContainerRuntimeCommandService containerRuntimeCommandService;
    private readonly ContainerLinkRepairService containerLinkRepairService;

    public CaiOperationsService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser())
    {
    }

    internal CaiOperationsService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
        : base(standardOutput, standardError)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        containerRuntimeCommandService = new ContainerRuntimeCommandService(stdout, stderr, manifestTomlParser);
        containerLinkRepairService = new ContainerLinkRepairService(stdout, stderr, ExecuteDockerCommandAsync);
    }

    public static Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunDockerCoreAsync(options.DockerArgs, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunStatusCoreAsync(options.Json, options.Verbose, options.Workspace, options.Container, cancellationToken);
    }

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunDoctorCoreAsync(options.Json, options.BuildTemplates, options.ResetLima, cancellationToken);
    }

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunDoctorFixCoreAsync(options.All, options.DryRun, options.Target, options.TargetArg, cancellationToken);
    }

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunDoctorCoreAsync(options.Json, buildTemplates: false, resetLima: false, cancellationToken);
    }

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSetupCoreAsync(
            dryRun: options.DryRun,
            verbose: options.Verbose,
            skipTemplates: options.SkipTemplates,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunExportCoreAsync(options.Output, options.DataVolume, options.Container, options.Workspace, cancellationToken);
    }

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => RunSyncCoreAsync(cancellationToken);

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunStopCoreAsync(
            containerName: options.Container,
            stopAll: options.All,
            remove: options.Remove,
            force: options.Force,
            exportFirst: options.Export,
            cancellationToken);
    }

    public Task<int> RunGcAsync(GcCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunGcCoreAsync(
            dryRun: options.DryRun,
            force: options.Force,
            includeImages: options.Images,
            ageValue: options.Age ?? "30d",
            cancellationToken);
    }

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunSshCleanupCoreAsync(options.DryRun, cancellationToken);
    }

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("check", options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("fix", options, cancellationToken);

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunTemplateUpgradeCoreAsync(options.Name, options.DryRun, cancellationToken);
    }

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunUpdateCoreAsync(
            dryRun: options.DryRun,
            stopContainers: options.StopContainers || options.Force,
            limaRecreate: options.LimaRecreate,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunRefreshCoreAsync(
            rebuild: options.Rebuild,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return RunUninstallCoreAsync(
            dryRun: options.DryRun,
            removeContainers: options.Containers,
            removeVolumes: options.Volumes,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => RunVersionCoreAsync(json: false, cancellationToken);

    public Task<int> RunSystemInitAsync(SystemInitCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemInitAsync(options, cancellationToken);
    }

    public Task<int> RunSystemLinkRepairAsync(SystemLinkRepairCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemLinkRepairAsync(options, cancellationToken);
    }

    public Task<int> RunSystemWatchLinksAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemWatchLinksAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return containerRuntimeCommandService.RunSystemDevcontainerInstallAsync(options, cancellationToken);
    }

    public Task<int> RunSystemDevcontainerInitAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerInitAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerStartAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerStartAsync(cancellationToken);

    public Task<int> RunSystemDevcontainerVerifySysboxAsync(CancellationToken cancellationToken)
        => containerRuntimeCommandService.RunSystemDevcontainerVerifySysboxAsync(cancellationToken);

    private Task<int> RunLinksSubcommandAsync(string subcommand, LinksSubcommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var containerName = string.IsNullOrWhiteSpace(options.Container) ? options.Name : options.Container;
        return RunLinksCoreAsync(subcommand, containerName, options.Workspace, options.DryRun, options.Quiet, cancellationToken);
    }
}
