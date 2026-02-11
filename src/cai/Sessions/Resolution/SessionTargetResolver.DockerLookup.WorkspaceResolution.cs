namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetDockerLookupService
{
    private async Task<ContainerLookupResult?> TryResolveConfiguredWorkspaceContainerAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return null;
        }

        var workspaceState = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceState.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceState.StandardOutput))
        {
            return null;
        }

        var configuredName = parsingValidationService.TryReadWorkspaceStringProperty(workspaceState.StandardOutput, "container_name");
        if (string.IsNullOrWhiteSpace(configuredName))
        {
            return null;
        }

        var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", configuredName],
            cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var labels = await ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal)
            ? ContainerLookupResult.Success(configuredName)
            : null;
    }

    private async Task<ContainerLookupResult> TryResolveGeneratedWorkspaceContainerAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var generated = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", generated],
            cancellationToken).ConfigureAwait(false);

        return generatedExists.ExitCode == 0
            ? ContainerLookupResult.Success(generated)
            : ContainerLookupResult.Empty();
    }
}
