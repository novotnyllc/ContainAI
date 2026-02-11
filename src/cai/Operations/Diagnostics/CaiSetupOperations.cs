using ContainAI.Cli.Host.Operations.Diagnostics.Setup;

namespace ContainAI.Cli.Host;

internal sealed class CaiSetupOperations : CaiRuntimeSupport
{
    private const string SetupUsage = "Usage: cai setup [--dry-run] [--verbose] [--skip-templates]";
    private const string RuntimeSocketPath = "/var/run/containai-docker.sock";

    private readonly CaiTemplateRestoreOperations templateRestoreOperations;
    private readonly Func<CancellationToken, Task<int>> runDoctorPostSetupAsync;

    public CaiSetupOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        CaiTemplateRestoreOperations templateRestoreOperations,
        Func<CancellationToken, Task<int>> runDoctorPostSetupAsync)
        : base(standardOutput, standardError)
    {
        this.templateRestoreOperations = templateRestoreOperations ?? throw new ArgumentNullException(nameof(templateRestoreOperations));
        this.runDoctorPostSetupAsync = runDoctorPostSetupAsync ?? throw new ArgumentNullException(nameof(runDoctorPostSetupAsync));
    }

    public async Task<int> RunSetupAsync(
        bool dryRun,
        bool verbose,
        bool skipTemplates,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            await WriteSetupUsageAsync().ConfigureAwait(false);
            return 0;
        }

        var setupPaths = ResolveSetupPaths();

        if (dryRun)
        {
            await WriteSetupDryRunAsync(setupPaths, skipTemplates).ConfigureAwait(false);
            return 0;
        }

        return await RunSetupCoreAsync(setupPaths, verbose, skipTemplates, cancellationToken).ConfigureAwait(false);
    }

    private Task WriteSetupUsageAsync() => stdout.WriteLineAsync(SetupUsage);

    private static SetupPaths ResolveSetupPaths()
    {
        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");

        return new SetupPaths(containAiDir, sshDir, sshKeyPath, RuntimeSocketPath);
    }

    private async Task WriteSetupDryRunAsync(SetupPaths setupPaths, bool skipTemplates)
    {
        await stdout.WriteLineAsync($"Would create {setupPaths.ContainAiDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would create {setupPaths.SshDir}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would generate SSH key {setupPaths.SshKeyPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync($"Would verify runtime socket {setupPaths.SocketPath}").ConfigureAwait(false);
        await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
        if (!skipTemplates)
        {
            await stdout.WriteLineAsync($"Would install templates to {ResolveTemplatesDirectory()}").ConfigureAwait(false);
        }
    }

    private async Task<int> RunSetupCoreAsync(
        SetupPaths setupPaths,
        bool verbose,
        bool skipTemplates,
        CancellationToken cancellationToken)
    {
        if (!await EnsureDockerCliAvailableForSetupAsync(cancellationToken).ConfigureAwait(false))
        {
            return 1;
        }

        EnsureSetupDirectories(setupPaths.ContainAiDir, setupPaths.SshDir);
        if (await EnsureSetupSshKeyAsync(setupPaths.SshKeyPath, cancellationToken).ConfigureAwait(false) != 0)
        {
            return 1;
        }

        await EnsureRuntimeSocketForSetupAsync(setupPaths.SocketPath, cancellationToken).ConfigureAwait(false);
        await EnsureSetupDockerContextAsync(setupPaths.SocketPath, verbose, cancellationToken).ConfigureAwait(false);

        if (!skipTemplates)
        {
            var templateResult = await templateRestoreOperations
                .RestoreTemplatesAsync(templateName: null, includeAll: true, cancellationToken)
                .ConfigureAwait(false);
            if (templateResult != 0 && verbose)
            {
                await stderr.WriteLineAsync("Template installation completed with warnings.").ConfigureAwait(false);
            }
        }

        var doctorExitCode = await runDoctorPostSetupAsync(cancellationToken).ConfigureAwait(false);
        if (doctorExitCode != 0)
        {
            await stderr.WriteLineAsync("Setup completed with warnings. Run `cai doctor` for details.").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Setup complete.").ConfigureAwait(false);
        return doctorExitCode;
    }

    private static void EnsureSetupDirectories(string containAiDir, string sshDir)
        => CaiSetupPrerequisiteHelper.EnsureSetupDirectories(containAiDir, sshDir);

    private async Task<bool> EnsureDockerCliAvailableForSetupAsync(CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureDockerCliAvailableAsync(cancellationToken)
            .ConfigureAwait(false);

    private async Task<int> EnsureSetupSshKeyAsync(string sshKeyPath, CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureSetupSshKeyAsync(sshKeyPath, cancellationToken)
            .ConfigureAwait(false);

    private static async Task EnsureRuntimeSocketForSetupAsync(string socketPath, CancellationToken cancellationToken)
        => await CaiSetupPrerequisiteHelper
            .EnsureRuntimeSocketForSetupAsync(socketPath, CommandSucceedsAsync, RunSetupProcessCaptureAsync, cancellationToken)
            .ConfigureAwait(false);

    private async Task EnsureSetupDockerContextAsync(string socketPath, bool verbose, CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureSetupDockerContextAsync(socketPath, verbose, cancellationToken)
            .ConfigureAwait(false);

    private CaiSetupPrerequisiteHelper CreateSetupPrerequisiteHelper()
        => new(stderr, CommandSucceedsAsync, RunSetupProcessCaptureAsync);

    private static async Task<CaiSetupPrerequisiteCommandResult> RunSetupProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return new CaiSetupPrerequisiteCommandResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }

    private readonly record struct SetupPaths(string ContainAiDir, string SshDir, string SshKeyPath, string SocketPath);
}
