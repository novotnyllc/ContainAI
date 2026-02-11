namespace ContainAI.Cli.Host.ContainerRuntime.Inspection;

internal readonly record struct ContainerRuntimeLinkEntryStateEvaluation(
    ContainerRuntimeLinkInspectionState State,
    string? CurrentTarget);
