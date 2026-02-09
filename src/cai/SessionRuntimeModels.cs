namespace ContainAI.Cli.Host;

internal enum SessionMode
{
    Run,
    Shell,
    Exec,
}

internal sealed record SessionCommandOptions(
    SessionMode Mode,
    string? Workspace,
    string? DataVolume,
    string? ExplicitConfig,
    string? Container,
    string? Template,
    string? ImageTag,
    string? Channel,
    string? Memory,
    string? Cpus,
    string? Credentials,
    bool AcknowledgeCredentialRisk,
    bool Fresh,
    bool Reset,
    bool Force,
    bool Detached,
    bool Quiet,
    bool Verbose,
    bool Debug,
    bool DryRun,
    IReadOnlyList<string> CommandArgs,
    List<string> EnvVars)
{
    public static SessionCommandOptions Create(SessionMode mode)
        => new(
            Mode: mode,
            Workspace: null,
            DataVolume: null,
            ExplicitConfig: null,
            Container: null,
            Template: null,
            ImageTag: null,
            Channel: null,
            Memory: null,
            Cpus: null,
            Credentials: null,
            AcknowledgeCredentialRisk: false,
            Fresh: false,
            Reset: false,
            Force: false,
            Detached: false,
            Quiet: false,
            Verbose: false,
            Debug: false,
            DryRun: false,
            CommandArgs: Array.Empty<string>(),
            EnvVars: []);
}

internal sealed record ResolutionResult<T>(bool Success, T? Value, string? Error, int ErrorCode)
{
    public static ResolutionResult<T> SuccessResult(T value) => new(true, value, null, 1);

    public static ResolutionResult<T> ErrorResult(string error, int errorCode = 1) => new(false, default, error, errorCode);
}

internal sealed record ContextSelectionResult(bool Success, string? Context, string? Error, int ErrorCode)
{
    public static ContextSelectionResult FromContext(string context) => new(true, context, null, 1);

    public static ContextSelectionResult FromError(string error, int errorCode = 1) => new(false, null, error, errorCode);
}

internal sealed record FindContainerByNameResult(bool Exists, string? Context, string? Error, int ErrorCode);

internal sealed record ContainerLookupResult(string? ContainerName, string? Error, int ErrorCode)
{
    public static ContainerLookupResult Success(string name) => new(name, null, 1);

    public static ContainerLookupResult Empty() => new(null, null, 1);

    public static ContainerLookupResult FromError(string error, int errorCode = 1) => new(null, error, errorCode);
}

internal sealed record ResolvedTarget(
    string ContainerName,
    string Workspace,
    string DataVolume,
    string Context,
    bool ShouldPersistState,
    bool CreatedByThisInvocation,
    bool GeneratedFromReset,
    string? Error,
    int ErrorCode)
{
    public static ResolvedTarget ErrorResult(string error, int errorCode = 1)
        => new(string.Empty, string.Empty, string.Empty, string.Empty, false, false, false, error, errorCode);
}

internal sealed record EnsuredSession(
    string ContainerName,
    string Workspace,
    string DataVolume,
    string Context,
    string SshPort,
    string? Error,
    int ErrorCode)
{
    public static EnsuredSession ErrorResult(string error, int errorCode = 1)
        => new(string.Empty, string.Empty, string.Empty, string.Empty, string.Empty, error, errorCode);
}

internal sealed record CreateContainerResult(string SshPort);

internal sealed record ContainerLabelState(bool Exists, bool IsOwned, string Workspace, string DataVolume, string SshPort, string State)
{
    public static ContainerLabelState NotFound() => new(false, false, string.Empty, string.Empty, string.Empty, string.Empty);
}

internal readonly record struct ProcessResult(int ExitCode, string StandardOutput, string StandardError);
