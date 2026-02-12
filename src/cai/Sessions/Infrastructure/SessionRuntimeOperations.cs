using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Infrastructure;

internal interface ISessionRuntimeOperations
{
    Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken);

    Task<ProcessResult> DockerCaptureAsync(
        string context,
        IReadOnlyList<string> dockerArgs,
        CancellationToken cancellationToken);

    Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken);

    Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken);

    string ResolveUserConfigPath();

    string ResolveSshPublicKeyPath();

    string FindConfigFile(string workspace, string? explicitConfig);

    string NormalizeWorkspacePath(string path);

    bool IsValidVolumeName(string name);

    string GenerateWorkspaceVolumeName(string workspace);

    string EscapeForSingleQuotedShell(string value);

    string TrimOrFallback(string? value, string fallback);
}

internal sealed class SessionRuntimeOperations : ISessionRuntimeOperations
{
    public Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerContextExistsAsync(context, cancellationToken);

    public Task<ProcessResult> DockerCaptureAsync(
        string context,
        IReadOnlyList<string> dockerArgs,
        CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerCaptureAsync(context, dockerArgs, cancellationToken);

    public Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunTomlAsync(operation, cancellationToken);

    public Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunProcessCaptureAsync(fileName, arguments, cancellationToken);

    public string ResolveUserConfigPath()
        => SessionRuntimePathHelpers.ResolveUserConfigPath();

    public string ResolveSshPublicKeyPath()
        => SessionRuntimePathHelpers.ResolveSshPublicKeyPath();

    public string FindConfigFile(string workspace, string? explicitConfig)
        => SessionRuntimePathHelpers.FindConfigFile(workspace, explicitConfig);

    public string NormalizeWorkspacePath(string path)
        => SessionRuntimePathHelpers.NormalizeWorkspacePath(path);

    public bool IsValidVolumeName(string name)
        => SessionRuntimeDockerHelpers.IsValidVolumeName(name);

    public string GenerateWorkspaceVolumeName(string workspace)
        => SessionRuntimeVolumeNameGenerator.GenerateWorkspaceVolumeName(workspace);

    public string EscapeForSingleQuotedShell(string value)
        => SessionRuntimeTextHelpers.EscapeForSingleQuotedShell(value);

    public string TrimOrFallback(string? value, string fallback)
        => SessionRuntimeTextHelpers.TrimOrFallback(value, fallback);
}
