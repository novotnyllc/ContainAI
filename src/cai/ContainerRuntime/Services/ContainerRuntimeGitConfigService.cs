using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed class ContainerRuntimeGitConfigService : IContainerRuntimeGitConfigService
{
    private readonly IContainerRuntimeExecutionContext context;

    public ContainerRuntimeGitConfigService(IContainerRuntimeExecutionContext context)
        => this.context = context ?? throw new ArgumentNullException(nameof(context));

    public async Task MigrateGitConfigAsync(string dataDir, bool quiet)
    {
        var oldPath = Path.Combine(dataDir, ".gitconfig");
        var newDir = Path.Combine(dataDir, "git");
        var newPath = Path.Combine(newDir, "gitconfig");

        if (!File.Exists(oldPath) || await context.IsSymlinkAsync(oldPath).ConfigureAwait(false))
        {
            return;
        }

        var oldInfo = new FileInfo(oldPath);
        if (oldInfo.Length == 0)
        {
            return;
        }

        var needsNewPath = !File.Exists(newPath) || new FileInfo(newPath).Length == 0;
        if (!needsNewPath)
        {
            return;
        }

        if (await context.IsSymlinkAsync(newDir).ConfigureAwait(false))
        {
            await context.StandardError.WriteLineAsync($"[WARN] {newDir} is a symlink - cannot migrate git config").ConfigureAwait(false);
            return;
        }

        Directory.CreateDirectory(newDir);
        if (await context.IsSymlinkAsync(newPath).ConfigureAwait(false))
        {
            await context.StandardError.WriteLineAsync($"[WARN] {newPath} is a symlink - cannot migrate git config").ConfigureAwait(false);
            return;
        }

        var tempPath = $"{newPath}.tmp.{Environment.ProcessId}";
        File.Copy(oldPath, tempPath, overwrite: true);
        File.Move(tempPath, newPath, overwrite: true);
        File.Delete(oldPath);
        await context.LogInfoAsync(quiet, $"Migrated git config from {oldPath} to {newPath}").ConfigureAwait(false);
    }

    public async Task SetupGitConfigAsync(string dataDir, string homeDir, bool quiet)
    {
        var destination = Path.Combine(homeDir, ".gitconfig");
        if (await context.IsSymlinkAsync(destination).ConfigureAwait(false))
        {
            return;
        }

        var source = Path.Combine(dataDir, "git", "gitconfig");
        if (!File.Exists(source) || new FileInfo(source).Length == 0)
        {
            return;
        }

        if (Directory.Exists(destination))
        {
            await context.StandardError.WriteLineAsync($"[WARN] Destination {destination} exists but is not a regular file - skipping").ConfigureAwait(false);
            return;
        }

        var tempDestination = $"{destination}.tmp.{Environment.ProcessId}";
        File.Copy(source, tempDestination, overwrite: true);
        File.Move(tempDestination, destination, overwrite: true);
        await context.LogInfoAsync(quiet, "Git config loaded from data volume").ConfigureAwait(false);
    }
}
