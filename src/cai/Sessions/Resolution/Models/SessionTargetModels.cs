namespace ContainAI.Cli.Host.Sessions.Resolution.Models;

internal sealed record SessionTargetVolumeSelection(string DataVolume, bool GeneratedFromReset);

internal sealed record SessionTargetContainerSelection(string ContainerName, bool CreatedByThisInvocation);
