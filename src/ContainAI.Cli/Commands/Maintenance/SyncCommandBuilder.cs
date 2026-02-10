using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class SyncCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("sync", "Run in-container sync operations.");
        command.SetAction((_, cancellationToken) => runtime.RunSyncAsync(cancellationToken));
        return command;
    }
}
