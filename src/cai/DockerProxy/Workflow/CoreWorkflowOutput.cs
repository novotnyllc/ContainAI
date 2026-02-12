namespace ContainAI.Cli.Host;

internal static class DockerProxyCreateCommandOutputBuilder
{
    public static async Task<List<string>> BuildManagedCreateArgumentsAsync(
        IReadOnlyList<string> dockerArgs,
        string contextName,
        string workspaceName,
        FeatureSettings settings,
        string sshPort,
        bool mountVolume,
        bool quiet,
        IDockerProxyCommandExecutor commandExecutor,
        IUtcClock clock,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var modifiedArgs = new List<string>(dockerArgs.Count + 24);
        foreach (var token in dockerArgs)
        {
            modifiedArgs.Add(token);
            if (!string.Equals(token, "run", StringComparison.Ordinal) && !string.Equals(token, "create", StringComparison.Ordinal))
            {
                continue;
            }

            modifiedArgs.Add("--runtime=sysbox-runc");

            if (mountVolume)
            {
                var volumeExists = await commandExecutor.RunCaptureAsync(
                    ["--context", contextName, "volume", "inspect", settings.DataVolume],
                    cancellationToken).ConfigureAwait(false);

                if (volumeExists.ExitCode == 0)
                {
                    modifiedArgs.Add("--mount");
                    modifiedArgs.Add($"type=volume,src={settings.DataVolume},dst=/mnt/agent-data,readonly=false");
                }
                else if (!quiet)
                {
                    await stderr.WriteLineAsync($"[cai-docker] Warning: Data volume {settings.DataVolume} not found - skipping mount").ConfigureAwait(false);
                }
            }

            modifiedArgs.Add("-e");
            modifiedArgs.Add($"CONTAINAI_SSH_PORT={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.managed=true");
            modifiedArgs.Add("--label");
            modifiedArgs.Add("containai.type=devcontainer");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.devcontainer.workspace={workspaceName}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.data-volume={settings.DataVolume}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.ssh-port={sshPort}");
            modifiedArgs.Add("--label");
            modifiedArgs.Add($"containai.created={clock.UtcNow:yyyy-MM-ddTHH:mm:ssZ}");
        }

        return modifiedArgs;
    }

    public static async Task WriteVerboseExecutionAsync(
        bool verbose,
        bool quiet,
        string contextName,
        IReadOnlyList<string> modifiedArgs,
        TextWriter stderr)
    {
        if (!verbose || quiet)
        {
            return;
        }

        await stderr.WriteLineAsync($"[cai-docker] Executing: docker --context {contextName} {string.Join(' ', modifiedArgs)}").ConfigureAwait(false);
    }
}
