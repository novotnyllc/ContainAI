namespace ContainAI.Cli.Host;

internal static class SessionTargetDockerLookupService
{
    public static async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            [
                "inspect",
                "--format",
                "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}",
                containerName,
            ],
            cancellationToken).ConfigureAwait(false);

        if (inspect.ExitCode != 0)
        {
            return ContainerLabelState.NotFound();
        }

        var parts = inspect.StandardOutput.Trim().Split('|');
        if (parts.Length < 6)
        {
            return ContainerLabelState.NotFound();
        }

        var managed = string.Equals(parts[0], SessionRuntimeConstants.ManagedLabelValue, StringComparison.Ordinal);
        var image = parts[4];
        var owned = managed || SessionRuntimeInfrastructure.IsContainAiImage(image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: SessionRuntimeInfrastructure.NormalizeNoValue(parts[1]),
            DataVolume: SessionRuntimeInfrastructure.NormalizeNoValue(parts[2]),
            SshPort: SessionRuntimeInfrastructure.NormalizeNoValue(parts[3]),
            State: SessionRuntimeInfrastructure.NormalizeNoValue(parts[5]));
    }

    public static async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await SessionTargetWorkspaceDiscoveryService.BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        var found = new List<string>();
        foreach (var context in contexts)
        {
            var inspect = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "docker",
                ["--context", context, "inspect", "--type", "container", "--", containerName],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                found.Add(context);
            }
        }

        if (found.Count == 0)
        {
            return new FindContainerByNameResult(false, null, null, 1);
        }

        if (found.Count > 1)
        {
            return new FindContainerByNameResult(false, null, $"Container '{containerName}' exists in multiple contexts: {string.Join(", ", found)}", 1);
        }

        return new FindContainerByNameResult(true, found[0], null, 1);
    }

    public static async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (File.Exists(configPath))
        {
            var ws = await SessionRuntimeInfrastructure.RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
                cancellationToken).ConfigureAwait(false);
            if (ws.ExitCode == 0 && !string.IsNullOrWhiteSpace(ws.StandardOutput))
            {
                var configuredName = SessionTargetParsingValidationService.TryReadWorkspaceStringProperty(ws.StandardOutput, "container_name");
                if (!string.IsNullOrWhiteSpace(configuredName))
                {
                    var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                        context,
                        ["inspect", "--type", "container", configuredName],
                        cancellationToken).ConfigureAwait(false);
                    if (inspect.ExitCode == 0)
                    {
                        var labels = await ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
                        if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
                        {
                            return ContainerLookupResult.Success(configuredName);
                        }
                    }
                }
            }
        }

        var byLabel = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return ContainerLookupResult.Empty();
        }

        var ids = byLabel.StandardOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (ids.Length > 1)
        {
            return ContainerLookupResult.FromError($"Multiple containers found for workspace: {workspace}");
        }

        if (ids.Length == 1)
        {
            var nameResult = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                context,
                ["inspect", "--format", "{{.Name}}", ids[0]],
                cancellationToken).ConfigureAwait(false);
            if (nameResult.ExitCode == 0)
            {
                return ContainerLookupResult.Success(nameResult.StandardOutput.Trim().TrimStart('/'));
            }
        }

        var generated = await SessionTargetWorkspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", generated],
            cancellationToken).ConfigureAwait(false);
        if (generatedExists.ExitCode == 0)
        {
            return ContainerLookupResult.Success(generated);
        }

        return ContainerLookupResult.Empty();
    }

    public static async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await SessionTargetWorkspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var candidate = baseName;

        for (var suffix = 1; suffix <= 99; suffix++)
        {
            var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
                context,
                ["inspect", "--type", "container", candidate],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode != 0)
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
            if (string.Equals(labels.Workspace, workspace, StringComparison.Ordinal))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            var suffixText = $"-{suffix + 1}";
            var maxBase = Math.Max(1, 24 - suffixText.Length);
            candidate = SessionRuntimeInfrastructure.TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBase)]) + suffixText;
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }
}
