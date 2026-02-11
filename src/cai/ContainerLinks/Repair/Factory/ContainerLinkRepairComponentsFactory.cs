namespace ContainAI.Cli.Host;

internal static class ContainerLinkRepairComponentsFactory
{
    public static ContainerLinkSpecSetLoader CreateSpecSetLoader(TextWriter standardError, DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        return new ContainerLinkSpecSetLoader(new ContainerLinkSpecReader(commandClient), standardError);
    }

    public static ContainerLinkEntryProcessor CreateEntryProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        var repairOperations = new ContainerLinkRepairOperations(commandClient);
        var reporter = new ContainerLinkRepairReporter(standardOutput);
        var stateReporter = new ContainerLinkEntryStateReporter(standardError, reporter);
        var repairExecutor = new ContainerLinkEntryRepairExecutor(standardError, repairOperations, reporter);
        return new ContainerLinkEntryProcessor(standardError, new ContainerLinkEntryInspector(commandClient), stateReporter, repairExecutor);
    }

    public static ContainerLinkCheckedTimestampUpdater CreateCheckedTimestampUpdater(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        var repairOperations = new ContainerLinkRepairOperations(commandClient);
        var reporter = new ContainerLinkRepairReporter(standardOutput);
        return new ContainerLinkCheckedTimestampUpdater(repairOperations, reporter, standardError);
    }
}
