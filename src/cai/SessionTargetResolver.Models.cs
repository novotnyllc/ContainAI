namespace ContainAI.Cli.Host;

internal sealed record SessionTargetVolumeSelection(string DataVolume, bool GeneratedFromReset);

internal sealed record SessionTargetContainerSelection(string ContainerName, bool CreatedByThisInvocation);
