namespace ContainAI.Cli.Host;

internal sealed partial class CaiSetupOperations
{
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
