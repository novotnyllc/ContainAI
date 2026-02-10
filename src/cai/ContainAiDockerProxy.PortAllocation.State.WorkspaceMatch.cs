namespace ContainAI.Cli.Host;

internal sealed partial class DockerProxyPortAllocationStateReader
{
    public async Task<bool> IsWorkspacePortMatchAsync(string contextName, string workspaceName, string port, CancellationToken cancellationToken)
    {
        var existingContainerPort = await commandExecutor.RunCaptureAsync(
            [
                "--context", contextName,
                "ps", "-a",
                "--filter", $"label=containai.devcontainer.workspace={workspaceName}",
                "--filter", "label=containai.ssh-port",
                "--format", "{{.Label \"containai.ssh-port\"}}",
            ],
            cancellationToken).ConfigureAwait(false);

        return existingContainerPort.ExitCode == 0 &&
               string.Equals(existingContainerPort.StandardOutput.Trim(), port, StringComparison.Ordinal);
    }
}
