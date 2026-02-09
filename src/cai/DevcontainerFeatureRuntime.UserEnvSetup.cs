namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureRuntime
{
    private sealed class DevcontainerUserEnvironmentSetup
    {
        private readonly DevcontainerProcessHelpers processHelpers;
        private readonly TextWriter stdout;

        public DevcontainerUserEnvironmentSetup(DevcontainerProcessHelpers processHelpers, TextWriter standardOutput)
        {
            this.processHelpers = processHelpers;
            stdout = standardOutput;
        }

        public async Task<string> DetectUserHomeAsync(string remoteUser, CancellationToken cancellationToken)
        {
            var candidate = remoteUser;
            if (string.Equals(candidate, "auto", StringComparison.Ordinal) || string.IsNullOrWhiteSpace(candidate))
            {
                candidate = await UserExistsAsync("vscode", cancellationToken).ConfigureAwait(false) ? "vscode"
                    : await UserExistsAsync("node", cancellationToken).ConfigureAwait(false) ? "node"
                    : Environment.GetEnvironmentVariable("USER") ?? "root";
            }

            if (await processHelpers.CommandExistsAsync("getent", cancellationToken).ConfigureAwait(false))
            {
                var result = await processHelpers.RunProcessCaptureAsync("getent", ["passwd", candidate], cancellationToken).ConfigureAwait(false);
                if (result.ExitCode == 0)
                {
                    var parts = result.StandardOutput.Trim().Split(':');
                    if (parts.Length >= 6 && Directory.Exists(parts[5]))
                    {
                        return parts[5];
                    }
                }
            }

            if (string.Equals(candidate, "root", StringComparison.Ordinal))
            {
                return "/root";
            }

            var conventionalPath = $"/home/{candidate}";
            if (Directory.Exists(conventionalPath))
            {
                return conventionalPath;
            }

            return Environment.GetEnvironmentVariable("HOME") ?? conventionalPath;
        }

        public async Task AddUserToDockerGroupIfPresentAsync(string user, CancellationToken cancellationToken)
        {
            if (!await UserExistsAsync(user, cancellationToken).ConfigureAwait(false))
            {
                return;
            }

            await processHelpers.RunAsRootAsync("usermod", ["-aG", "docker", user], cancellationToken).ConfigureAwait(false);
            await stdout.WriteLineAsync($"    Added {user} to docker group").ConfigureAwait(false);
        }

        private async Task<bool> UserExistsAsync(string user, CancellationToken cancellationToken)
        {
            var result = await processHelpers.RunProcessCaptureAsync("id", ["-u", user], cancellationToken).ConfigureAwait(false);
            return result.ExitCode == 0;
        }
    }
}
