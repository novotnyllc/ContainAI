namespace ContainAI.Cli.Host;

internal static class CaiCommandRuntimeHandlersFactory
{
    public static CaiCommandRuntimeHandlers Create(
        AcpProxyRunner proxyRunner,
        IManifestTomlParser manifestTomlParser,
        TextWriter standardOutput,
        TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(proxyRunner);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);

        var sessionRuntime = new SessionCommandRuntime(standardOutput, standardError);
        var operationsService = new CaiOperationsService(standardOutput, standardError, manifestTomlParser);
        var configManifestService = new CaiConfigManifestService(standardOutput, standardError, manifestTomlParser);
        var importService = new CaiImportService(standardOutput, standardError, manifestTomlParser);
        var installRuntime = new InstallCommandRuntime();
        var examplesRuntime = new ExamplesCommandRuntime();

        return new CaiCommandRuntimeHandlers(
            new CaiRuntimeOperationsCommandHandler(operationsService),
            new CaiRuntimeConfigCommandHandler(configManifestService),
            new CaiRuntimeImportCommandHandler(importService),
            new CaiRuntimeSessionCommandHandler(sessionRuntime),
            new CaiRuntimeSystemCommandHandler(operationsService),
            new CaiRuntimeToolsCommandHandler(proxyRunner, installRuntime, examplesRuntime));
    }
}
