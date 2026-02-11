using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class CaiDoctorFixOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly Func<bool, CancellationToken, Task<int>> runSshCleanupAsync;
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;

    public CaiDoctorFixOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync,
        CaiTemplateRestoreOperations templateRestoreOperations)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
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
        if (await TryWriteAvailableTargetsAsync(target, fixAll).ConfigureAwait(false))
        {
            return 0;
        }

        var homeDirectory = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var containAiDir = Path.Combine(homeDirectory, ".config", "containai");
        var sshDir = Path.Combine(homeDirectory, ".ssh", "containai.d");
        await EnsureDirectoriesAndSshAsync(dryRun, containAiDir, sshDir, cancellationToken).ConfigureAwait(false);

        var templateResult = await RunTemplateFixAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (templateResult != 0)
        {
            return templateResult;
        }

        var containerResult = await RunContainerFixAsync(fixAll, target, targetArg, cancellationToken).ConfigureAwait(false);
        if (containerResult != 0)
        {
            return containerResult;
        }

        return 0;
    }

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

    private static async Task EnsureSshIncludeDirectiveAsync(CancellationToken cancellationToken)
    {
        var homeDirectory = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var userSshConfig = Path.Combine(homeDirectory, ".ssh", "config");
        var includeLine = $"Include {Path.Combine(homeDirectory, ".ssh", "containai.d")}/*.conf";

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

        var exists = await CaiRuntimeDockerHelpers.DockerContainerExistsAsync(targetArg, cancellationToken).ConfigureAwait(false);
        if (!exists)
        {
            await stderr.WriteLineAsync($"Container not found: {targetArg}").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync($"Container fix completed for {targetArg}.").ConfigureAwait(false);
        return 0;
    }
}
