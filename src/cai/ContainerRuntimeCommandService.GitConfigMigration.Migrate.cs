namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed partial class ContainerRuntimeGitConfigService
{
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
}
