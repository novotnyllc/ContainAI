namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFileAndProcessInspection
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
