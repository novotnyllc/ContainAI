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
