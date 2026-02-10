using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Meta;

internal static class VersionCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        var versionCommand = new Command("version");

        var jsonOption = new Option<bool>("--json")
        {
            Description = "Emit version information as JSON.",
        };
        versionCommand.Options.Add(jsonOption);

        versionCommand.SetAction(async (parseResult, cancellationToken) =>
        {
            if (parseResult.GetValue(jsonOption))
            {
                cancellationToken.ThrowIfCancellationRequested();
                await console.OutputWriter.WriteLineAsync(RootCommandBuilder.GetVersionJson()).ConfigureAwait(false);
                return 0;
            }

            return await runtime.RunVersionAsync(cancellationToken).ConfigureAwait(false);
        });

        return versionCommand;
    }
}
