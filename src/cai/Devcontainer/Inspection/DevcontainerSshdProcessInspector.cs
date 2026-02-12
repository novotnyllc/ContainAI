using ContainAI.Cli.Host.Devcontainer.ProcessExecution;

namespace ContainAI.Cli.Host.Devcontainer.Inspection;

internal sealed class DevcontainerSshdProcessInspector(
    DevcontainerFileSystem fileSystem,
    IDevcontainerProcessExecution processExecution) : IDevcontainerSshdProcessInspector
{
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

        return processExecution.IsProcessAlive(pid);
    }
}
