namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations
{
    private async Task EnsureDirectoriesAndSshAsync(
        bool dryRun,
        string containAiDir,
        string sshDir,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir} and {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would ensure SSH include directive and cleanup stale SSH configs").ConfigureAwait(false);
            return;
        }

        Directory.CreateDirectory(containAiDir);
        Directory.CreateDirectory(sshDir);
        await EnsureSshIncludeDirectiveAsync(cancellationToken).ConfigureAwait(false);
        _ = await runSshCleanupAsync(false, cancellationToken).ConfigureAwait(false);
    }

    private static async Task EnsureSshIncludeDirectiveAsync(CancellationToken cancellationToken)
    {
        var userSshConfig = Path.Combine(ResolveHomeDirectory(), ".ssh", "config");
        var includeLine = $"Include {Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d")}/*.conf";

        Directory.CreateDirectory(Path.GetDirectoryName(userSshConfig)!);
        if (!File.Exists(userSshConfig))
        {
            await File.WriteAllTextAsync(userSshConfig, includeLine + Environment.NewLine, cancellationToken).ConfigureAwait(false);
            return;
        }

        var content = await File.ReadAllTextAsync(userSshConfig, cancellationToken).ConfigureAwait(false);
        if (content.Contains(includeLine, StringComparison.Ordinal))
        {
            return;
        }

        var normalized = content.TrimEnd();
        var merged = string.IsNullOrWhiteSpace(normalized)
            ? includeLine + Environment.NewLine
            : normalized + Environment.NewLine + includeLine + Environment.NewLine;
        await File.WriteAllTextAsync(userSshConfig, merged, cancellationToken).ConfigureAwait(false);
    }
}
