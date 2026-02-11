namespace ContainAI.Cli.Host;

internal sealed class CaiOperationsCommandHandlers
{
    public CaiOperationsCommandHandlers(
        CaiDiagnosticsCommandHandler diagnosticsHandler,
        CaiMaintenanceCommandHandler maintenanceHandler,
        CaiSystemCommandHandler systemHandler,
        CaiTemplateSshGcCommandHandler templateSshGcHandler)
    {
        DiagnosticsHandler = diagnosticsHandler ?? throw new ArgumentNullException(nameof(diagnosticsHandler));
        MaintenanceHandler = maintenanceHandler ?? throw new ArgumentNullException(nameof(maintenanceHandler));
        SystemHandler = systemHandler ?? throw new ArgumentNullException(nameof(systemHandler));
        TemplateSshGcHandler = templateSshGcHandler ?? throw new ArgumentNullException(nameof(templateSshGcHandler));
    }

    public CaiDiagnosticsCommandHandler DiagnosticsHandler { get; }

    public CaiMaintenanceCommandHandler MaintenanceHandler { get; }

    public CaiSystemCommandHandler SystemHandler { get; }

    public CaiTemplateSshGcCommandHandler TemplateSshGcHandler { get; }
}
