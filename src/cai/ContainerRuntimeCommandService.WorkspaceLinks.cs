using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeWorkspaceLinkService
{
    Task SetupWorkspaceSymlinkAsync(string workspaceDir, bool quiet);
}

internal sealed class ContainerRuntimeWorkspaceLinkService : IContainerRuntimeWorkspaceLinkService
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeWorkspaceLinkService(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task SetupWorkspaceSymlinkAsync(string workspaceDir, bool quiet)
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
            await context.StandardError.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be absolute path: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        if (!IsAllowedWorkspacePrefix(hostWorkspace))
        {
            await context.StandardError.WriteLineAsync($"[WARN] CAI_HOST_WORKSPACE must be under /home/, /tmp/, /mnt/, /workspaces/, or /Users/: {hostWorkspace}").ConfigureAwait(false);
            return;
        }

        var parent = Path.GetDirectoryName(hostWorkspace);
        if (string.IsNullOrWhiteSpace(parent))
        {
            return;
        }

        await context.RunAsRootAsync("mkdir", ["-p", parent]).ConfigureAwait(false);
        await context.RunAsRootAsync("ln", ["-sfn", workspaceDir, hostWorkspace]).ConfigureAwait(false);
        await context.LogInfoAsync(quiet, $"Workspace symlink created: {hostWorkspace} -> {workspaceDir}").ConfigureAwait(false);
    }

    private static bool IsAllowedWorkspacePrefix(string path)
        => path.StartsWith("/home/", StringComparison.Ordinal)
           || path.StartsWith("/tmp/", StringComparison.Ordinal)
           || path.StartsWith("/mnt/", StringComparison.Ordinal)
           || path.StartsWith("/workspaces/", StringComparison.Ordinal)
           || path.StartsWith("/Users/", StringComparison.Ordinal);
}
