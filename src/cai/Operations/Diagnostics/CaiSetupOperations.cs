namespace ContainAI.Cli.Host;

internal sealed class CaiSetupOperations : CaiRuntimeSupport
{
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
            await stdout.WriteLineAsync("Usage: cai setup [--dry-run] [--verbose] [--skip-templates]").ConfigureAwait(false);
            return 0;
        }

        var home = ResolveHomeDirectory();
        var containAiDir = Path.Combine(home, ".config", "containai");
        var sshDir = Path.Combine(home, ".ssh", "containai.d");
        var sshKeyPath = Path.Combine(containAiDir, "id_containai");
        var socketPath = "/var/run/containai-docker.sock";

        if (dryRun)
        {
            await stdout.WriteLineAsync($"Would create {containAiDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would create {sshDir}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would generate SSH key {sshKeyPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync($"Would verify runtime socket {socketPath}").ConfigureAwait(false);
            await stdout.WriteLineAsync("Would create Docker context containai-docker").ConfigureAwait(false);
            if (!skipTemplates)
            {
                await stdout.WriteLineAsync($"Would install templates to {ResolveTemplatesDirectory()}").ConfigureAwait(false);
            }

            return 0;
        }

        if (!await EnsureDockerCliAvailableForSetupAsync(cancellationToken).ConfigureAwait(false))
        {
            return 1;
        }

        EnsureSetupDirectories(containAiDir, sshDir);
        if (await EnsureSetupSshKeyAsync(sshKeyPath, cancellationToken).ConfigureAwait(false) != 0)
        {
            return 1;
        }

        await EnsureRuntimeSocketForSetupAsync(socketPath, cancellationToken).ConfigureAwait(false);
        await EnsureSetupDockerContextAsync(socketPath, verbose, cancellationToken).ConfigureAwait(false);

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
    {
        Directory.CreateDirectory(containAiDir);
        Directory.CreateDirectory(sshDir);
    }

    private async Task<bool> EnsureDockerCliAvailableForSetupAsync(CancellationToken cancellationToken)
    {
        if (await CommandSucceedsAsync("docker", ["--version"], cancellationToken).ConfigureAwait(false))
        {
            return true;
        }

        await stderr.WriteLineAsync("Docker CLI is required for setup.").ConfigureAwait(false);
        return false;
    }

    private async Task<int> EnsureSetupSshKeyAsync(string sshKeyPath, CancellationToken cancellationToken)
    {
        if (File.Exists(sshKeyPath))
        {
            return 0;
        }

        var keygen = await RunProcessCaptureAsync(
            "ssh-keygen",
            ["-t", "ed25519", "-N", string.Empty, "-f", sshKeyPath, "-C", "containai"],
            cancellationToken).ConfigureAwait(false);
        if (keygen.ExitCode == 0)
        {
            return 0;
        }

        await stderr.WriteLineAsync(keygen.StandardError.Trim()).ConfigureAwait(false);
        return 1;
    }

    private static async Task EnsureRuntimeSocketForSetupAsync(string socketPath, CancellationToken cancellationToken)
    {
        if (!File.Exists(socketPath))
        {
            if (await CommandSucceedsAsync("systemctl", ["cat", "containai-docker.service"], cancellationToken).ConfigureAwait(false))
            {
                await RunProcessCaptureAsync("systemctl", ["start", "containai-docker.service"], cancellationToken).ConfigureAwait(false);
            }
        }

        if (!File.Exists(socketPath) && OperatingSystem.IsMacOS())
        {
            await RunProcessCaptureAsync("limactl", ["start", "containai"], cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task EnsureSetupDockerContextAsync(string socketPath, bool verbose, CancellationToken cancellationToken)
    {
        if (File.Exists(socketPath))
        {
            var createContext = await RunProcessCaptureAsync(
                "docker",
                ["context", "create", "containai-docker", "--docker", $"host=unix://{socketPath}"],
                cancellationToken).ConfigureAwait(false);
            if (createContext.ExitCode != 0 && verbose)
            {
                var error = createContext.StandardError.Trim();
                if (!string.IsNullOrWhiteSpace(error))
                {
                    await stderr.WriteLineAsync(error).ConfigureAwait(false);
                }
            }

            return;
        }

        await stderr.WriteLineAsync($"Setup warning: runtime socket not found at {socketPath}.").ConfigureAwait(false);
    }
}
