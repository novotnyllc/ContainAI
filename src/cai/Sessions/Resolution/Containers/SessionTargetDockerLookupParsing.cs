using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal static class SessionTargetDockerLookupParsing
{
    private const int LabelInspectFieldCount = 6;

    internal static bool TryParseContainerLabelFields(string inspectOutput, int exitCode, out ContainerLabelFields fields)
    {
        if (exitCode != 0)
        {
            fields = default;
            return false;
        }

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

    internal static ContainerLabelState BuildContainerLabelState(ContainerLabelFields fields)
    {
        var managed = string.Equals(fields.ManagedLabel, SessionRuntimeConstants.ManagedLabelValue, StringComparison.Ordinal);
        var owned = managed || SessionRuntimeDockerHelpers.IsContainAiImage(fields.Image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: SessionRuntimeTextHelpers.NormalizeNoValue(fields.WorkspaceLabel),
            DataVolume: SessionRuntimeTextHelpers.NormalizeNoValue(fields.DataVolumeLabel),
            SshPort: SessionRuntimeTextHelpers.NormalizeNoValue(fields.SshPortLabel),
            State: SessionRuntimeTextHelpers.NormalizeNoValue(fields.State));
    }

    internal static string ParseContainerName(string inspectOutput)
        => inspectOutput.Trim().TrimStart('/');

    internal static string[] ParseDockerOutputLines(string output)
        => output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}

internal readonly record struct ContainerLabelFields(
    string ManagedLabel,
    string WorkspaceLabel,
    string DataVolumeLabel,
    string SshPortLabel,
    string Image,
    string State);
