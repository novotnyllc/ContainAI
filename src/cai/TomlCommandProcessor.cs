using System.Text.RegularExpressions;

namespace ContainAI.Cli.Host;

internal sealed record TomlCommandResult(int ExitCode, string StandardOutput, string StandardError);

internal static partial class TomlCommandProcessor
{
    private static readonly Regex WorkspaceKeyRegex = WorkspaceKeyRegexFactory();
    private static readonly Regex GlobalKeyRegex = GlobalKeyRegexFactory();

    private static TomlCommandResult Execute(TomlCommandArguments arguments, Func<TomlCommandArguments, TomlCommandResult> operation)
    {
        if (string.IsNullOrWhiteSpace(arguments.FilePath))
        {
            return new TomlCommandResult(1, string.Empty, "Error: --file is required");
        }

        return operation(arguments);
    }

    private static TomlCommandArguments CreateArguments(string filePath)
        => new()
        {
            FilePath = filePath,
        };
}
