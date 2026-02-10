using System.Collections.Frozen;
using System.CommandLine.Parsing;

namespace ContainAI.Cli;

internal static class RootCommandCompletionHelpers
{
    internal static (string Line, int Cursor) NormalizeCompletionInput(string line, int position)
    {
        if (string.IsNullOrEmpty(line))
        {
            return (string.Empty, 0);
        }

        var clampedPosition = Math.Clamp(position, 0, line.Length);
        var start = 0;
        while (start < line.Length && char.IsWhiteSpace(line[start]))
        {
            start++;
        }

        var end = start;
        while (end < line.Length && !char.IsWhiteSpace(line[end]))
        {
            end++;
        }

        if (end == start)
        {
            return (line, clampedPosition);
        }

        var invocationToken = line[start..end];
        var invocationName = Path.GetFileNameWithoutExtension(invocationToken);
        if (string.Equals(invocationName, "cai", StringComparison.OrdinalIgnoreCase))
        {
            var trimStart = end;
            while (trimStart < line.Length && char.IsWhiteSpace(line[trimStart]))
            {
                trimStart++;
            }

            return (line[trimStart..], Math.Max(0, clampedPosition - trimStart));
        }

        if (string.Equals(invocationName, "containai-docker", StringComparison.OrdinalIgnoreCase)
            || string.Equals(invocationName, "docker-containai", StringComparison.OrdinalIgnoreCase))
        {
            var trimStart = end;
            while (trimStart < line.Length && char.IsWhiteSpace(line[trimStart]))
            {
                trimStart++;
            }

            var remainder = line[trimStart..];
            var rewritten = string.IsNullOrWhiteSpace(remainder)
                ? "docker "
                : $"docker {remainder}";
            var cursor = "docker ".Length + Math.Max(0, clampedPosition - trimStart);
            return (rewritten, Math.Clamp(cursor, 0, rewritten.Length));
        }

        return (line, clampedPosition);
    }

    internal static string[] NormalizeCompletionArguments(string line, FrozenSet<string> knownCommands)
    {
        var normalized = CommandLineParser.SplitCommandLine(line).ToArray();
        if (normalized.Length == 0)
        {
            return Array.Empty<string>();
        }

        normalized = normalized switch
        {
            ["help"] => ["--help"],
            ["help", .. var helpArgs] when helpArgs.Length > 0 => [.. helpArgs, "--help"],
            ["--refresh", .. var refreshArgs] => ["refresh", .. refreshArgs],
            ["-v" or "--version", .. var versionArgs] => ["version", .. versionArgs],
            _ => normalized,
        };

        if (ShouldImplicitRunForCompletion(normalized, knownCommands))
        {
            return ["run", .. normalized];
        }

        return normalized;
    }

    private static bool ShouldImplicitRunForCompletion(string[] args, FrozenSet<string> knownCommands)
    {
        if (args.Length == 0)
        {
            return false;
        }

        var firstToken = args[0];
        if (firstToken is "--help" or "-h")
        {
            return false;
        }

        if (firstToken.StartsWith('-'))
        {
            return true;
        }

        if (knownCommands.Any(command => command.StartsWith(firstToken, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        return !knownCommands.Contains(firstToken);
    }
}
