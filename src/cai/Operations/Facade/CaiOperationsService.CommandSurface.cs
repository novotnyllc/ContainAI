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
}
