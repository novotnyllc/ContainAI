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

internal readonly record struct CaiSetupPrerequisiteCommandResult(int ExitCode, string StandardOutput, string StandardError);

internal sealed class CaiSetupPrerequisiteHelper
{
    private readonly TextWriter standardError;
    private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<bool>> commandSucceedsAsync;
    private readonly Func<string, IReadOnlyList<string>, CancellationToken, Task<CaiSetupPrerequisiteCommandResult>> runProcessCaptureAsync;

    public CaiSetupPrerequisiteHelper(
        TextWriter standardError,
        Func<string, IReadOnlyList<string>, CancellationToken, Task<bool>> commandSucceedsAsync,
        Func<string, IReadOnlyList<string>, CancellationToken, Task<CaiSetupPrerequisiteCommandResult>> runProcessCaptureAsync)
    {
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.commandSucceedsAsync = commandSucceedsAsync ?? throw new ArgumentNullException(nameof(commandSucceedsAsync));
        this.runProcessCaptureAsync = runProcessCaptureAsync ?? throw new ArgumentNullException(nameof(runProcessCaptureAsync));
    }

    public static void EnsureSetupDirectories(string containAiDir, string sshDir)
    {
        Directory.CreateDirectory(containAiDir);
        Directory.CreateDirectory(sshDir);
    }

    public async Task<bool> EnsureDockerCliAvailableAsync(CancellationToken cancellationToken)
    {
        if (await commandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false))
        {
            return true;
        }

        await standardError.WriteLineAsync("Docker CLI is required for setup.").ConfigureAwait(false);
        return false;
    }

    public async Task<int> EnsureSetupSshKeyAsync(string sshKeyPath, CancellationToken cancellationToken)
    {
        if (File.Exists(sshKeyPath))
        {
            return 0;
        }

        var keygen = await runProcessCaptureAsync(
            "ssh-keygen",
            ["-t", "ed25519", "-N", string.Empty, "-f", sshKeyPath, "-C", "containai"],
            cancellationToken).ConfigureAwait(false);
        if (keygen.ExitCode == 0)
        {
            return 0;
        }

        await standardError.WriteLineAsync(keygen.StandardError.Trim()).ConfigureAwait(false);
        return 1;
    }

    public static async Task EnsureRuntimeSocketForSetupAsync(
        string socketPath,
        Func<string, IReadOnlyList<string>, CancellationToken, Task<bool>> commandSucceedsAsync,
        Func<string, IReadOnlyList<string>, CancellationToken, Task<CaiSetupPrerequisiteCommandResult>> runProcessCaptureAsync,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(socketPath))
        {
            if (await commandSucceedsAsync("systemctl", ["cat", "containai-docker.service"], cancellationToken).ConfigureAwait(false))
            {
                _ = await runProcessCaptureAsync("systemctl", ["start", "containai-docker.service"], cancellationToken).ConfigureAwait(false);
            }
        }

        if (!File.Exists(socketPath) && OperatingSystem.IsMacOS())
        {
            _ = await runProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
        }
    }

    public async Task EnsureSetupDockerContextAsync(string socketPath, bool verbose, CancellationToken cancellationToken)
    {
        if (File.Exists(socketPath))
        {
            var createContext = await runProcessCaptureAsync(
                "docker",
                ["context", "create", "containai-docker", "--docker", $"host=unix://{socketPath}"],
                cancellationToken).ConfigureAwait(false);
            if (createContext.ExitCode != 0 && verbose)
            {
                var error = createContext.StandardError.Trim();
                if (!string.IsNullOrWhiteSpace(error))
                {
                    await standardError.WriteLineAsync(error).ConfigureAwait(false);
                }
            }

            return;
        }

        await standardError.WriteLineAsync($"Setup warning: runtime socket not found at {socketPath}.").ConfigureAwait(false);
    }
}
