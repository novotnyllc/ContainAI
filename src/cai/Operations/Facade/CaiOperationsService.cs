using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CaiOperationsService : CaiRuntimeSupport
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    private readonly ContainerRuntimeCommandService containerRuntimeCommandService;
    private readonly ContainerLinkRepairService containerLinkRepairService;
    private readonly CaiDiagnosticsAndSetupOperations diagnosticsAndSetupOperations;
    private readonly CaiMaintenanceOperations maintenanceOperations;
    private readonly CaiTemplateSshAndGcOperations templateSshAndGcOperations;

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

        containerRuntimeCommandService = new ContainerRuntimeCommandService(
            stdout,
            stderr,
            manifestTomlParser,
            new ContainerRuntimeOptionParser());
        containerLinkRepairService = new ContainerLinkRepairService(stdout, stderr, ExecuteDockerCommandAsync);

        CaiDiagnosticsAndSetupOperations diagnostics = null!;
        CaiMaintenanceOperations maintenance = null!;
        CaiTemplateSshAndGcOperations templateSshAndGc = null!;

        maintenance = new CaiMaintenanceOperations(
            stdout,
            stderr,
            containerLinkRepairService,
            (outputJson, buildTemplates, resetLima, cancellationToken) => diagnostics.RunDoctorAsync(outputJson, buildTemplates, resetLima, cancellationToken));

        templateSshAndGc = new CaiTemplateSshAndGcOperations(
            stdout,
            stderr,
            ContainAiImagePrefixes,
            (output, explicitVolume, container, workspace, cancellationToken) => maintenance.RunExportAsync(output, explicitVolume, container, workspace, cancellationToken));

        diagnostics = new CaiDiagnosticsAndSetupOperations(
            stdout,
            stderr,
            (dryRun, cancellationToken) => templateSshAndGc.RunSshCleanupAsync(dryRun, cancellationToken));

        diagnosticsAndSetupOperations = diagnostics;
        maintenanceOperations = maintenance;
        templateSshAndGcOperations = templateSshAndGc;
    }

    public static Task<int> RunDockerAsync(DockerCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return CaiDiagnosticsAndSetupOperations.RunDockerAsync(options.DockerArgs, cancellationToken);
    }

    public Task<int> RunStatusAsync(StatusCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunStatusAsync(options.Json, options.Verbose, options.Workspace, options.Container, cancellationToken);
    }

    public Task<int> RunDoctorAsync(DoctorCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorAsync(options.Json, options.BuildTemplates, options.ResetLima, cancellationToken);
    }

    public Task<int> RunDoctorFixAsync(DoctorFixCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorFixAsync(options.All, options.DryRun, options.Target, options.TargetArg, cancellationToken);
    }

    public Task<int> RunValidateAsync(ValidateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunDoctorAsync(options.Json, buildTemplates: false, resetLima: false, cancellationToken);
    }

    public Task<int> RunSetupAsync(SetupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return diagnosticsAndSetupOperations.RunSetupAsync(
            dryRun: options.DryRun,
            verbose: options.Verbose,
            skipTemplates: options.SkipTemplates,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunVersionAsync(CancellationToken cancellationToken)
        => diagnosticsAndSetupOperations.RunVersionAsync(json: false, cancellationToken);

    public Task<int> RunExportAsync(ExportCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunExportAsync(options.Output, options.DataVolume, options.Container, options.Workspace, cancellationToken);
    }

    public Task<int> RunSyncAsync(CancellationToken cancellationToken)
        => maintenanceOperations.RunSyncAsync(cancellationToken);

    public Task<int> RunUpdateAsync(UpdateCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunUpdateAsync(
            dryRun: options.DryRun,
            stopContainers: options.StopContainers || options.Force,
            limaRecreate: options.LimaRecreate,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunRefreshAsync(RefreshCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunRefreshAsync(
            rebuild: options.Rebuild,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunUninstallAsync(UninstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return maintenanceOperations.RunUninstallAsync(
            dryRun: options.DryRun,
            removeContainers: options.Containers,
            removeVolumes: options.Volumes,
            showHelp: false,
            cancellationToken);
    }

    public Task<int> RunLinksCheckAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("check", options, cancellationToken);

    public Task<int> RunLinksFixAsync(LinksSubcommandOptions options, CancellationToken cancellationToken)
        => RunLinksSubcommandAsync("fix", options, cancellationToken);

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

    public Task<int> RunStopAsync(StopCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunStopAsync(
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
        return templateSshAndGcOperations.RunGcAsync(
            dryRun: options.DryRun,
            force: options.Force,
            includeImages: options.Images,
            ageValue: options.Age ?? "30d",
            cancellationToken);
    }

    public Task<int> RunSshCleanupAsync(SshCleanupCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunSshCleanupAsync(options.DryRun, cancellationToken);
    }

    public Task<int> RunTemplateUpgradeAsync(TemplateUpgradeCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        return templateSshAndGcOperations.RunTemplateUpgradeAsync(options.Name, options.DryRun, cancellationToken);
    }

    private Task<int> RunLinksSubcommandAsync(string subcommand, LinksSubcommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);
        var containerName = string.IsNullOrWhiteSpace(options.Container) ? options.Name : options.Container;
        return maintenanceOperations.RunLinksAsync(subcommand, containerName, options.Workspace, options.DryRun, options.Quiet, cancellationToken);
    }
}
