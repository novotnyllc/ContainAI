namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorFixOperations : CaiRuntimeSupport
{
    private readonly Func<bool, CancellationToken, Task<int>> runSshCleanupAsync;
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;

    public CaiDoctorFixOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync,
        CaiTemplateRestoreOperations templateRestoreOperations)
        : base(standardOutput, standardError)
    {
        this.runSshCleanupAsync = runSshCleanupAsync ?? throw new ArgumentNullException(nameof(runSshCleanupAsync));
        this.templateRestoreOperations = templateRestoreOperations ?? throw new ArgumentNullException(nameof(templateRestoreOperations));
    }

    public async Task<int> RunDoctorFixAsync(
        bool fixAll,
        bool dryRun,
        string? target,
        string? targetArg,
        CancellationToken cancellationToken)
    {
        if (target is null && !fixAll)
        {
            await stdout.WriteLineAsync("Available doctor fix targets:").ConfigureAwait(false);
            await stdout.WriteLineAsync("  --all").ConfigureAwait(false);
            await stdout.WriteLineAsync("  container [--all|<name>]").ConfigureAwait(false);
            await stdout.WriteLineAsync("  template [--all|<name>]").ConfigureAwait(false);
            return 0;
        }

        var containAiDir = Path.Combine(ResolveHomeDirectory(), ".config", "containai");
        var sshDir = Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");
        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir} and {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would ensure SSH include directive and cleanup stale SSH configs").ConfigureAwait(false);
        }
        else
        {
            Directory.CreateDirectory(containAiDir);
            Directory.CreateDirectory(sshDir);
            await EnsureSshIncludeDirectiveAsync(cancellationToken).ConfigureAwait(false);
            _ = await runSshCleanupAsync(false, cancellationToken).ConfigureAwait(false);
        }

        if (fixAll || string.Equals(target, "template", StringComparison.Ordinal))
        {
            var templateResult = await templateRestoreOperations
                .RestoreTemplatesAsync(
                    targetArg,
                    includeAll: fixAll || string.Equals(targetArg, "--all", StringComparison.Ordinal),
                    cancellationToken)
                .ConfigureAwait(false);
            if (templateResult != 0)
            {
                return templateResult;
            }
        }

        if (fixAll || string.Equals(target, "container", StringComparison.Ordinal))
        {
            if (string.IsNullOrWhiteSpace(targetArg) || string.Equals(targetArg, "--all", StringComparison.Ordinal))
            {
                await stdout.WriteLineAsync("Container fix completed (SSH cleanup applied).").ConfigureAwait(false);
            }
            else
            {
                var exists = await DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
                if (!exists)
                {
                    await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
                    return 1;
                }

                await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
            }
        }

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
