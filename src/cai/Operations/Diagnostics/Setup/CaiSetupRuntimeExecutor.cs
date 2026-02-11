using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host.Operations.Diagnostics.Setup;

internal sealed class CaiSetupRuntimeExecutor
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly CaiTemplateRestoreOperations templateRestoreOperations;
    private readonly Func<CancellationToken, Task<int>> runDoctorPostSetupAsync;

    public CaiSetupRuntimeExecutor(
        TextWriter standardOutput,
        TextWriter standardError,
        CaiTemplateRestoreOperations caiTemplateRestoreOperations,
        Func<CancellationToken, Task<int>> runDoctorPostSetupAsync)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        templateRestoreOperations = caiTemplateRestoreOperations ?? throw new ArgumentNullException(nameof(caiTemplateRestoreOperations));
        this.runDoctorPostSetupAsync = runDoctorPostSetupAsync ?? throw new ArgumentNullException(nameof(runDoctorPostSetupAsync));
    }

    public async Task<int> RunAsync(
        CaiSetupPaths setupPaths,
        bool verbose,
        bool skipTemplates,
        CancellationToken cancellationToken)
    {
        if (!await EnsureDockerCliAvailableForSetupAsync(cancellationToken).ConfigureAwait(false))
        {
            return 1;
        }

        CaiSetupPrerequisiteHelper.EnsureSetupDirectories(setupPaths.ContainAiDir, setupPaths.SshDir);
        if (await EnsureSetupSshKeyAsync(setupPaths.SshKeyPath, cancellationToken).ConfigureAwait(false) != 0)
        {
            return 1;
        }

        await CaiSetupPrerequisiteHelper
            .EnsureRuntimeSocketForSetupAsync(setupPaths.SocketPath, CaiRuntimeProcessRunner.CommandSucceedsAsync, RunSetupProcessCaptureAsync, cancellationToken)
            .ConfigureAwait(false);

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

    private async Task<bool> EnsureDockerCliAvailableForSetupAsync(CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureDockerCliAvailableAsync(cancellationToken)
            .ConfigureAwait(false);

    private async Task<int> EnsureSetupSshKeyAsync(string sshKeyPath, CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureSetupSshKeyAsync(sshKeyPath, cancellationToken)
            .ConfigureAwait(false);

    private async Task EnsureSetupDockerContextAsync(string socketPath, bool verbose, CancellationToken cancellationToken)
        => await CreateSetupPrerequisiteHelper()
            .EnsureSetupDockerContextAsync(socketPath, verbose, cancellationToken)
            .ConfigureAwait(false);

    private CaiSetupPrerequisiteHelper CreateSetupPrerequisiteHelper()
        => new(stderr, CaiRuntimeProcessRunner.CommandSucceedsAsync, RunSetupProcessCaptureAsync);

    private static async Task<CaiSetupPrerequisiteCommandResult> RunSetupProcessCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        var result = await CaiRuntimeProcessRunner.RunProcessCaptureAsync(executable, arguments, cancellationToken).ConfigureAwait(false);
        return new CaiSetupPrerequisiteCommandResult(result.ExitCode, result.StandardOutput, result.StandardError);
    }
}
