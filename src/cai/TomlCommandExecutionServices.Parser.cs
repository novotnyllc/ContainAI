namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => parser.TryGetNestedValue(table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => parser.GetWorkspaceState(table, workspacePath);
}
