namespace ContainAI.Cli.Host;

internal static class SessionRuntimeInfrastructure
{
    public static Task<bool> DockerContextExistsAsync(string context, CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerContextExistsAsync(context, cancellationToken);

    public static Task<ProcessResult> DockerCaptureAsync(
        string context,
        IReadOnlyList<string> dockerArgs,
        CancellationToken cancellationToken)
        => SessionRuntimeDockerHelpers.DockerCaptureAsync(context, dockerArgs, cancellationToken);

    public static bool IsContainAiImage(string image) => SessionRuntimeDockerHelpers.IsContainAiImage(image);

    public static bool IsValidVolumeName(string name) => SessionRuntimeDockerHelpers.IsValidVolumeName(name);

    public static string ResolveImage(SessionCommandOptions options) => SessionRuntimeDockerHelpers.ResolveImage(options);

    public static string NormalizeWorkspacePath(string path) => SessionRuntimePathHelpers.NormalizeWorkspacePath(path);

    public static string ExpandHome(string value) => SessionRuntimePathHelpers.ExpandHome(value);

    public static string ResolveHomeDirectory() => SessionRuntimePathHelpers.ResolveHomeDirectory();

    public static string ResolveConfigDirectory() => SessionRuntimePathHelpers.ResolveConfigDirectory();

    public static string ResolveUserConfigPath() => SessionRuntimePathHelpers.ResolveUserConfigPath();

    public static string ResolveSshPrivateKeyPath() => SessionRuntimePathHelpers.ResolveSshPrivateKeyPath();

    public static string ResolveSshPublicKeyPath() => SessionRuntimePathHelpers.ResolveSshPublicKeyPath();

    public static string ResolveKnownHostsFilePath() => SessionRuntimePathHelpers.ResolveKnownHostsFilePath();

    public static string ResolveSshConfigDir() => SessionRuntimePathHelpers.ResolveSshConfigDir();

    public static string FindConfigFile(string workspace, string? explicitConfig)
        => SessionRuntimePathHelpers.FindConfigFile(workspace, explicitConfig);

    public static Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunTomlAsync(operation, cancellationToken);

    public static Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TextWriter errorWriter,
        CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunProcessInteractiveAsync(fileName, arguments, errorWriter, cancellationToken);

    public static Task<ProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
        => SessionRuntimeProcessHelpers.RunProcessCaptureAsync(fileName, arguments, cancellationToken);

    public static string ResolveHostTimeZone() => SessionRuntimeSystemHelpers.ResolveHostTimeZone();

    public static void ParsePortsFromSocketTable(string content, HashSet<int> destination)
        => SessionRuntimeSystemHelpers.ParsePortsFromSocketTable(content, destination);

    public static string EscapeForSingleQuotedShell(string value)
        => SessionRuntimeTextHelpers.EscapeForSingleQuotedShell(value);

    public static string ReplaceFirstToken(string knownHostsLine, string hostToken)
        => SessionRuntimeTextHelpers.ReplaceFirstToken(knownHostsLine, hostToken);

    public static string NormalizeNoValue(string value)
        => SessionRuntimeTextHelpers.NormalizeNoValue(value);

    public static string SanitizeNameComponent(string value, string fallback)
        => SessionRuntimeTextHelpers.SanitizeNameComponent(value, fallback);

    public static string SanitizeHostname(string value) => SessionRuntimeTextHelpers.SanitizeHostname(value);

    public static string TrimTrailingDash(string value) => SessionRuntimeTextHelpers.TrimTrailingDash(value);

    public static string GenerateWorkspaceVolumeName(string workspace)
        => SessionRuntimeVolumeNameGenerator.GenerateWorkspaceVolumeName(workspace);

    public static string TrimOrFallback(string? value, string fallback)
        => SessionRuntimeTextHelpers.TrimOrFallback(value, fallback);
}
