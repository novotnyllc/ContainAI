using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal sealed class DevcontainerUidMappingInspector(DevcontainerFileSystem fileSystem) : IDevcontainerUidMappingInspector
{
    public async Task<bool> HasUidMappingIsolationAsync(CancellationToken cancellationToken)
    {
        if (!fileSystem.FileExists("/proc/self/uid_map"))
        {
            return false;
        }

        var lines = await fileSystem.ReadAllLinesAsync("/proc/self/uid_map", cancellationToken).ConfigureAwait(false);
        foreach (var line in lines)
        {
            var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (fields.Length >= 3 && fields[0] == "0")
            {
                return fields[1] != "0";
            }
        }

        return false;
    }
}
