namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task SetupWorkspaceSymlinkAsync(string workspaceDir, bool quiet)
    {
        var hostWorkspace = Environment.GetEnvironmentVariable("CAI_HOST_WORKSPACE");
        if (string.IsNullOrWhiteSpace(hostWorkspace))
        {
            return;
        }

        if (string.Equals(hostWorkspace, workspaceDir, StringComparison.Ordinal))
        {
            return;
        }

        if (!Path.IsPathRooted(hostWorkspace))
        {
            await stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be absolute path: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        if (!IsAllowedWorkspacePrefix(hostWorkspace))
        {
            await stderr.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be under /home/, /tmp/, /mnt/, /workspaces/, or /Users/: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        var parent = Path.GetDirectoryName(hostWorkspace);
        if (string.IsNullOrWhiteSpace(parent))
        {
            return;
        }

        await RunAsRootAsync("mkdir", ["-p", parent]).ConfigureAwait(false);
        await RunAsRootAsync("ln", ["-sfn", workspaceDir, hostWorkspace]).ConfigureAwait(false);
        await LogInfoAsync(quiet, $"Workspace symlink created: {hostWorkspace} -> {workspaceDir}").ConfigureAwait(false);
    }

    private static bool IsAllowedWorkspacePrefix(string path) => path.StartsWith("/home/", StringComparison.Ordinal) ||
               path.StartsWith("/tmp/", StringComparison.Ordinal) ||
               path.StartsWith("/mnt/", StringComparison.Ordinal) ||
               path.StartsWith("/workspaces/", StringComparison.Ordinal) ||
               path.StartsWith("/Users/", StringComparison.Ordinal);
}
