using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal interface IDevcontainerSysboxMountInspector
{
    Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerSysboxMountInspector(DevcontainerFileSystem fileSystem) : IDevcontainerSysboxMountInspector
{
    public async Task<bool> IsSysboxFsMountedAsync(CancellationToken cancellationToken)
    {
        if (!fileSystem.FileExists("/proc/mounts"))
        {
            return false;
        }

        var mounts = await fileSystem.ReadAllLinesAsync("/proc/mounts", cancellationToken).ConfigureAwait(false);
        foreach (var line in mounts)
        {
            var fields = line.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (fields.Length >= 3 &&
                (string.Equals(fields[2], "sysboxfs", StringComparison.Ordinal) ||
                 string.Equals(fields[2], "fuse.sysboxfs", StringComparison.Ordinal)))
            {
                return true;
            }
        }

        return false;
    }
}
