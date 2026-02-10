namespace ContainAI.Cli.Host;

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
