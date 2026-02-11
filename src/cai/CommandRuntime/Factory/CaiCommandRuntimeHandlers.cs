namespace ContainAI.Cli.Host;

internal sealed class CaiCommandRuntimeHandlers
{
    public CaiCommandRuntimeHandlers(
        CaiRuntimeOperationsCommandHandler operationsHandler,
        CaiRuntimeConfigCommandHandler configHandler,
        CaiRuntimeImportCommandHandler importHandler,
        CaiRuntimeSessionCommandHandler sessionHandler,
        CaiRuntimeSystemCommandHandler systemHandler,
        CaiRuntimeToolsCommandHandler toolsHandler)
    {
        OperationsHandler = operationsHandler ?? throw new ArgumentNullException(nameof(operationsHandler));
        ConfigHandler = configHandler ?? throw new ArgumentNullException(nameof(configHandler));
        ImportHandler = importHandler ?? throw new ArgumentNullException(nameof(importHandler));
        SessionHandler = sessionHandler ?? throw new ArgumentNullException(nameof(sessionHandler));
        SystemHandler = systemHandler ?? throw new ArgumentNullException(nameof(systemHandler));
        ToolsHandler = toolsHandler ?? throw new ArgumentNullException(nameof(toolsHandler));
    }

    public CaiRuntimeOperationsCommandHandler OperationsHandler { get; }

    public CaiRuntimeConfigCommandHandler ConfigHandler { get; }

    public CaiRuntimeImportCommandHandler ImportHandler { get; }

    public CaiRuntimeSessionCommandHandler SessionHandler { get; }

    public CaiRuntimeSystemCommandHandler SystemHandler { get; }

    public CaiRuntimeToolsCommandHandler ToolsHandler { get; }
}
