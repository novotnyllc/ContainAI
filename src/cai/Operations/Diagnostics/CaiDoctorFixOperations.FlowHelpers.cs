namespace ContainAI.Cli.Host;

internal sealed partial class CaiDoctorFixOperations
{
    private async Task<bool> TryWriteAvailableTargetsAsync(string? target, bool fixAll)
    {
        if (target is not null || fixAll)
        {
            return false;
        }

        await stdout.WriteLineAsync("Available doctor fix targets:").ConfigureAwait(false);
        await stdout.WriteLineAsync("  --all").ConfigureAwait(false);
        await stdout.WriteLineAsync("  container [--all|<name>]").ConfigureAwait(false);
        await stdout.WriteLineAsync("  template [--all|<name>]").ConfigureAwait(false);
        return true;
    }

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

    private async Task<int> RunTemplateFixAsync(
        bool fixAll,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (!fixAll && !string.Equals(target, "template", StringComparison.Ordinal))
        {
            return 0;
        }

        return await templateRestoreOperations
            .RestoreTemplatesAsync(
                targetArg,
                includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal),
                cancellationToken)
            .ConfigureAwait(false);
    }

    private async Task<int> RunContainerFixAsync(
        bool fixAll,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (!fixAll && !string.Equals(target, "container", StringComparison.Ordinal))
        {
            return 0;
        }

        if (string.IsNullOrWhiteSpace(targetArg) || string.Equals(targetArg, "--all", StringComparison.Ordinal))
        {
            await stdout.WriteLineAsync("Container fix completed (SSH cleanup applied).").ConfigureAwait(false);
            return 0;
        }

        var exists = await DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
        if (!exists)
        {
            await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
        return 0;
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
