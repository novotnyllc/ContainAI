using System.Collections.Frozen;
using System.CommandLine;
using System.CommandLine.Parsing;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static class CompletionCommandBuilder
{
    internal static Command CreateCompletionCommand(RootCommand root, ICaiConsole console)
    {
        var completionCommand = new Command("completion", "Resolve completions for shell integration.");

        var suggestCommand = new Command("suggest", "Resolve completions for shell integration.")
        {
            Hidden = true,
        };
        var lineOption = new Option<string>("--line")
        {
            Description = "Full command line as typed in the shell.",
            Required = true,
        };
        var positionOption = new Option<int?>("--position")
        {
            Description = "Cursor position in the command line text.",
        };

        suggestCommand.Options.Add(lineOption);
        suggestCommand.Options.Add(positionOption);
        suggestCommand.SetAction(async (parseResult, cancellationToken) =>
        {
            cancellationToken.ThrowIfCancellationRequested();

            var line = parseResult.GetValue(lineOption) ?? string.Empty;
            var requestedPosition = parseResult.GetValue(positionOption) ?? line.Length;
            var normalized = RootCommandBuilder.NormalizeCompletionInput(line, requestedPosition);
            var knownCommands = root.Subcommands
                .Select(static command => command.Name)
                .ToFrozenSet(StringComparer.Ordinal);
            var completionArgs = RootCommandBuilder.NormalizeCompletionArguments(normalized.Line, knownCommands);
            var completionResult = CommandLineParser.Parse(root, completionArgs, configuration: null);

            foreach (var completion in completionResult.GetCompletions(position: normalized.Cursor))
            {
                var value = string.IsNullOrWhiteSpace(completion.InsertText) ? completion.Label : completion.InsertText;
                if (string.IsNullOrWhiteSpace(value))
                {
                    continue;
                }

                await console.OutputWriter.WriteLineAsync(value).ConfigureAwait(false);
            }

            return 0;
        });

        completionCommand.Subcommands.Add(suggestCommand);

        return completionCommand;
    }
}
