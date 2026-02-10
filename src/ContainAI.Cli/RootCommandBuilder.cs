using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static class RootCommandBuilder
{
    public static RootCommand Build(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(console);
        return RootCommandComposition.Create(runtime, console);
    }

    internal static string[] BuildArgumentList(string[]? parsedArgs, IReadOnlyList<string> unmatchedTokens)
        => RootCommandArgumentHelpers.BuildArgumentList(parsedArgs, unmatchedTokens);

    internal static (string Line, int Cursor) NormalizeCompletionInput(string line, int position)
        => RootCommandCompletionHelpers.NormalizeCompletionInput(line, position);

    internal static string[] NormalizeCompletionArguments(string line, System.Collections.Frozen.FrozenSet<string> knownCommands)
        => RootCommandCompletionHelpers.NormalizeCompletionArguments(line, knownCommands);

    internal static string ExpandHome(string path) => RootCommandPathHelpers.ExpandHome(path);

    internal static string GetVersionJson() => RootCommandVersionHelpers.GetVersionJson();
}
