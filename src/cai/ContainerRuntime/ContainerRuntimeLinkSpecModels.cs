namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal readonly record struct ContainerRuntimeLinkSpecRawEntry(
    string? LinkPath,
    string? TargetPath,
    bool RemoveFirst);

internal readonly record struct ContainerRuntimeLinkSpecValidatedEntry(
    string LinkPath,
    string TargetPath,
    bool RemoveFirst);
