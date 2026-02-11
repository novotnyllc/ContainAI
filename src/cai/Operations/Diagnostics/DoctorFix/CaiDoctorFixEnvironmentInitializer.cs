using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixEnvironmentInitializer
{
    Task InitializeAsync(bool dryRun, CancellationToken cancellationToken);
}

internal sealed class CaiDoctorFixEnvironmentInitializer : ICaiDoctorFixEnvironmentInitializer
{
    private readonly TextWriter stdout;
    private readonly Func<bool, CancellationToken, Task<int>> runSshCleanupAsync;

    public CaiDoctorFixEnvironmentInitializer(
        TextWriter standardOutput,
        Func<bool, CancellationToken, Task<int>> runSshCleanupAsync)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        this.runSshCleanupAsync = runSshCleanupAsync ?? throw new ArgumentNullException(nameof(runSshCleanupAsync));
    }

    public async Task InitializeAsync(bool dryRun, CancellationToken cancellationToken)
    {
        var homeDirectory = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var containAiDir = Path.Combine(homeDirectory, ".config", "containai");
        var sshDir = Path.Combine(homeDirectory, ".ssh", "containai.d");

        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir} and {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would ensure SSH include directive and cleanup stale SSH configs").ConfigureAwait(false);
            return;
        }

        Directory.CreateDirectory(containAiDir);
        Directory.CreateDirectory(sshDir);
        await EnsureSshIncludeDirectiveAsync(homeDirectory, cancellationToken).ConfigureAwait(false);
        _ = await runSshCleanupAsync(false, cancellationToken).ConfigureAwait(false);
    }

    private static async Task EnsureSshIncludeDirectiveAsync(string homeDirectory, CancellationToken cancellationToken)
    {
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
}
