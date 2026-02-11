namespace ContainAI.Cli.Host;

internal interface ISessionRuntimeOperations
{
    Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken);

    Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken);

    Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);

    string ResolveUserConfigPath();

    string FindConfigFile(string workspace, string? explicitConfig);

    string NormalizeWorkspacePath(string path);

    bool IsValidVolumeName(string name);

    string GenerateWorkspaceVolumeName(string workspace);
}

internal sealed class SessionRuntimeOperations : ISessionRuntimeOperations
{
    public Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerContextExistsAsync(context, cancellationToken);

    public Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.RunTomlAsync(operation, cancellationToken);

    public Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.RunProcessCaptureAsync(fileName, arguments, cancellationToken);

    public string ResolveUserConfigPath()
        => SessionRuntimeInfrastructure.ResolveUserConfigPath();

    public string FindConfigFile(string workspace, string? explicitConfig)
        => SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);

    public string NormalizeWorkspacePath(string path)
        => SessionRuntimeInfrastructure.NormalizeWorkspacePath(path);

    public bool IsValidVolumeName(string name)
        => SessionRuntimeInfrastructure.IsValidVolumeName(name);

    public string GenerateWorkspaceVolumeName(string workspace)
        => SessionRuntimeInfrastructure.GenerateWorkspaceVolumeName(workspace);
}
