using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class SshCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("ssh", "Manage SSH integration.");

        var cleanup = new Command("cleanup", "Remove stale SSH host configs.");
        var dryRunOption = new Option<bool>("--dry-run");
        cleanup.Options.Add(dryRunOption);
        cleanup.SetAction((parseResult, cancellationToken) =>
            runtime.RunSshCleanupAsync(
                new SshCleanupCommandOptions(
                    DryRun: parseResult.GetValue(dryRunOption)),
                cancellationToken));

        command.Subcommands.Add(cleanup);
        return command;
    }
}
