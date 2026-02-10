namespace ContainAI.Cli.Host;

internal enum DockerProxyCreateCommandParseStatus
{
    Passthrough,
    SetupMissing,
    ManagedCreate,
}

internal sealed record DockerProxyWorkspaceDescriptor(string Name, string SanitizedName);

internal sealed record DockerProxyCreateCommandRequest(
    FeatureSettings Settings,
    DockerProxyWorkspaceDescriptor Workspace,
    string ContainAiConfigDir,
    string LockPath);

internal sealed record DockerProxyCreateCommandParseResult(DockerProxyCreateCommandParseStatus Status, DockerProxyCreateCommandRequest? Request)
{
    public static DockerProxyCreateCommandParseResult Passthrough { get; } = new(DockerProxyCreateCommandParseStatus.Passthrough, null);
}

internal static class DockerProxyCreateCommandRequestParser
{
    public static async Task<DockerProxyCreateCommandParseResult> ParseAsync(
        IReadOnlyList<string> dockerArgs,
        string contextName,
        IDockerProxyArgumentParser argumentParser,
        IDevcontainerFeatureSettingsParser featureSettingsParser,
        IDockerProxyCommandExecutor commandExecutor,
        IContainAiSystemEnvironment environment,
        TextWriter stderr,
        CancellationToken cancellationToken)
    {
        var labels = argumentParser.ExtractDevcontainerLabels(dockerArgs);
        if (string.IsNullOrWhiteSpace(labels.ConfigFile) || !featureSettingsParser.TryReadFeatureSettings(labels.ConfigFile!, stderr, out var settings))
        {
            return DockerProxyCreateCommandParseResult.Passthrough;
        }

        if (!settings.HasContainAiFeature)
        {
            return DockerProxyCreateCommandParseResult.Passthrough;
        }

        var contextProbe = await commandExecutor.RunCaptureAsync(["context", "inspect", contextName], cancellationToken).ConfigureAwait(false);
        if (contextProbe.ExitCode != 0)
        {
            await stderr.WriteLineAsync("ContainAI: Not set up. Run: cai setup").ConfigureAwait(false);
            return new DockerProxyCreateCommandParseResult(DockerProxyCreateCommandParseStatus.SetupMissing, null);
        }

        var workspace = ResolveWorkspace(labels, argumentParser);
        var containAiConfigDir = Path.Combine(environment.ResolveHomeDirectory(), ".config", "containai");
        var lockPath = Path.Combine(containAiConfigDir, ".ssh-port.lock");
        var request = new DockerProxyCreateCommandRequest(settings, workspace, containAiConfigDir, lockPath);
        return new DockerProxyCreateCommandParseResult(DockerProxyCreateCommandParseStatus.ManagedCreate, request);
    }

    private static DockerProxyWorkspaceDescriptor ResolveWorkspace(DevcontainerLabels labels, IDockerProxyArgumentParser argumentParser)
    {
        var workspaceName = Path.GetFileName(labels.LocalFolder ?? "workspace");
        if (string.IsNullOrWhiteSpace(workspaceName))
        {
            workspaceName = "workspace";
        }

        return new DockerProxyWorkspaceDescriptor(workspaceName, argumentParser.SanitizeWorkspaceName(workspaceName));
    }
}
