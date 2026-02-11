namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed partial class ContainerRuntimeGitConfigService
{
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
