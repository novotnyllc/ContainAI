using ContainAI.Cli.Host.Operations.Diagnostics.Setup;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations
{
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
}
