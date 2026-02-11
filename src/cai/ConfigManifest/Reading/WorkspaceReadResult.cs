namespace ContainAI.Cli.Host.ConfigManifest.Reading;

internal readonly record struct WorkspaceReadResult(WorkspaceReadState State, string? Value = null)
{
    public static WorkspaceReadResult ExecutionError { get; } = new(WorkspaceReadState.ExecutionError);
    public static WorkspaceReadResult Missing { get; } = new(WorkspaceReadState.Missing);

    public static WorkspaceReadResult Found(string value) => new(WorkspaceReadState.Found, value);
}
