namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    private static bool TryParseContainerLabelFields(string inspectOutput, out ContainerLabelFields fields)
    {
        var parts = inspectOutput.Trim().Split('|');
        if (parts.Length < LabelInspectFieldCount)
        {
            fields = default;
            return false;
        }

        fields = new ContainerLabelFields(
            parts[0],
            parts[1],
            parts[2],
            parts[3],
            parts[4],
            parts[5]);
        return true;
    }

    private static ContainerLabelState BuildContainerLabelState(ContainerLabelFields fields)
    {
        var managed = string.Equals(fields.ManagedLabel, SessionRuntimeConstants.ManagedLabelValue, StringComparison.Ordinal);
        var owned = managed || SessionRuntimeInfrastructure.IsContainAiImage(fields.Image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: SessionRuntimeInfrastructure.NormalizeNoValue(fields.WorkspaceLabel),
            DataVolume: SessionRuntimeInfrastructure.NormalizeNoValue(fields.DataVolumeLabel),
            SshPort: SessionRuntimeInfrastructure.NormalizeNoValue(fields.SshPortLabel),
            State: SessionRuntimeInfrastructure.NormalizeNoValue(fields.State));
    }

    private static string ParseContainerName(string inspectOutput)
        => inspectOutput.Trim().TrimStart('/');

    private static string[] ParseDockerOutputLines(string output)
        => output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private readonly record struct ContainerLabelFields(
        string ManagedLabel,
        string WorkspaceLabel,
        string DataVolumeLabel,
        string SshPortLabel,
        string Image,
        string State);
}
