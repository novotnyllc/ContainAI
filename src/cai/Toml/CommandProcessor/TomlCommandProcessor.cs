using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed record TomlCommandResult(int ExitCode, string StandardOutput, string StandardError);

internal static class TomlCommandProcessor
{
    private static readonly Regex WorkspaceKeyRegex = TomlCommandRegexProvider.WorkspaceKeyRegex;
    private static readonly Regex GlobalKeyRegex = TomlCommandRegexProvider.GlobalKeyRegex;

    private static readonly ITomlCommandFileIo FileIo = new TomlCommandFileIo();
    private static readonly ITomlCommandParser Parser = new TomlCommandParser();
    private static readonly ITomlCommandSerializer Serializer = new TomlCommandSerializer();
    private static readonly ITomlCommandUpdater Updater = new TomlCommandUpdater();
    private static readonly ITomlCommandValidator Validator = new TomlCommandValidator(Parser);

    private static readonly TomlCommandExecutionServices ExecutionServices =
        new(FileIo, Parser, Serializer, Updater, Validator);

    private static readonly TomlCommandQueryExecutor QueryExecutor = new(ExecutionServices);
    private static readonly TomlCommandSetUnsetExecutor SetUnsetExecutor =
        new(ExecutionServices, WorkspaceKeyRegex, GlobalKeyRegex);

    public static TomlCommandResult GetKey(string filePath, string key)
        => Execute(filePath, () => QueryExecutor.GetKey(filePath, key));

    public static TomlCommandResult GetJson(string filePath)
        => Execute(filePath, () => QueryExecutor.GetJson(filePath));

    public static TomlCommandResult Exists(string filePath, string key)
        => Execute(filePath, () => QueryExecutor.Exists(filePath, key));

    public static TomlCommandResult GetEnv(string filePath)
        => Execute(filePath, () => QueryExecutor.GetEnv(filePath));

    public static TomlCommandResult GetWorkspace(string filePath, string workspacePath)
        => Execute(filePath, () => QueryExecutor.GetWorkspace(filePath, workspacePath));

    public static TomlCommandResult EmitAgents(string filePath)
        => Execute(filePath, () => QueryExecutor.EmitAgents(filePath));

    public static TomlCommandResult SetWorkspaceKey(string filePath, string workspacePath, string key, string value)
        => Execute(filePath, () => SetUnsetExecutor.SetWorkspaceKey(filePath, workspacePath, key, value));

    public static TomlCommandResult UnsetWorkspaceKey(string filePath, string workspacePath, string key)
        => Execute(filePath, () => SetUnsetExecutor.UnsetWorkspaceKey(filePath, workspacePath, key));

    public static TomlCommandResult SetKey(string filePath, string key, string value)
        => Execute(filePath, () => SetUnsetExecutor.SetKey(filePath, key, value));

    public static TomlCommandResult UnsetKey(string filePath, string key)
        => Execute(filePath, () => SetUnsetExecutor.UnsetKey(filePath, key));

    private static TomlCommandResult Execute(string filePath, Func<TomlCommandResult> operation)
    {
        if (string.IsNullOrWhiteSpace(filePath))
        {
            return new TomlCommandResult(1, string.Empty, "Error: --file is required");
        }

        return operation();
    }
}
