using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal static class CaiOperationsCommandHandlersFactory
{
    private static readonly string[] ContainAiImagePrefixes =
    [
        "containai:",
        "ghcr.io/containai/",
        "ghcr.io/novotnyllc/containai",
    ];

    public static CaiOperationsCommandHandlers Create(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        var containerRuntimeCommandService = new ContainerRuntimeCommandService(
            standardOutput,
            standardError,
            manifestTomlParser,
            new ContainerRuntimeOptionParser());

        var containerLinkRepairService = new ContainerLinkRepairService(
            standardOutput,
            standardError,
            CaiRuntimeDockerHelpers.ExecuteDockerCommandAsync);

        var sshCleanupOperations = new CaiSshCleanupOperations(standardOutput, standardError);
        var diagnosticsOperations = new CaiDiagnosticsAndSetupOperations(
            standardOutput,
            standardError,
            sshCleanupOperations.RunSshCleanupAsync);

        var maintenanceOperations = new CaiMaintenanceOperations(
            standardOutput,
            standardError,
            containerLinkRepairService,
            diagnosticsOperations.RunDoctorAsync);

        var templateSshAndGcOperations = new CaiTemplateSshAndGcOperations(
            standardOutput,
            standardError,
            ContainAiImagePrefixes,
            maintenanceOperations.RunExportAsync,
            sshCleanupOperations);

        return new CaiOperationsCommandHandlers(
            new CaiDiagnosticsCommandHandler(diagnosticsOperations),
            new CaiMaintenanceCommandHandler(maintenanceOperations),
            new CaiSystemCommandHandler(containerRuntimeCommandService),
            new CaiTemplateSshGcCommandHandler(templateSshAndGcOperations));
    }
}
