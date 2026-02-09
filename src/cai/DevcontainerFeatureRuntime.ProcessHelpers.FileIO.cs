namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed partial class DevcontainerProcessHelpers
    {
        public bool IsSymlink(string path)
        {
            try
            {
                var attributes = fileSystem.GetAttributes(path);
                return (attributes & FileAttributes.ReparsePoint) != 0;
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
            catch (ArgumentException)
            {
                return false;
            }
            catch (NotSupportedException)
            {
                return false;
            }
        }

        public async Task<bool> IsSshdRunningFromPidFileAsync(string pidFilePath, CancellationToken cancellationToken)
        {
            if (!fileSystem.FileExists(pidFilePath))
            {
                return false;
            }

            var pidRaw = await fileSystem.ReadAllTextAsync(pidFilePath, cancellationToken).ConfigureAwait(false);
            if (!int.TryParse(pidRaw.Trim(), out var pid))
            {
                return false;
            }

            if (!fileSystem.DirectoryExists($"/proc/{pid}"))
            {
                return false;
            }

            var commPath = $"/proc/{pid}/comm";
            if (fileSystem.FileExists(commPath))
            {
                var comm = (await fileSystem.ReadAllTextAsync(commPath, cancellationToken).ConfigureAwait(false)).Trim();
                return string.Equals(comm, "sshd", StringComparison.Ordinal);
            }

            return IsProcessAlive(pid);
        }

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
}
