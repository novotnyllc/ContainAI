using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Commands.Maintenance;

internal static class InstallCommandBuilder
{
    internal static Command Build(ICaiCommandRuntime runtime)
    {
        var command = new Command("install", "Install ContainAI into local user directories.");
        var localOption = new Option<bool>("--local")
        {
            Description = "Require local install payload resolution.",
        };
        var yesOption = new Option<bool>("--yes")
        {
            Description = "Auto-confirm installer actions.",
        };
        var noSetupOption = new Option<bool>("--no-setup")
        {
            Description = "Skip automatic setup/update after install.",
        };
        var installDirOption = new Option<string?>("--install-dir")
        {
            Description = "Installation directory (overrides CAI_INSTALL_DIR).",
        };
        var binDirOption = new Option<string?>("--bin-dir")
        {
            Description = "Wrapper binary directory (overrides CAI_BIN_DIR).",
        };
        var channelOption = new Option<string?>("--channel")
        {
            Description = "Optional installer channel hint.",
        };
        channelOption.AcceptOnlyFromAmong("stable", "nightly");
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose installer logging.",
        };

        command.Options.Add(localOption);
        command.Options.Add(yesOption);
        command.Options.Add(noSetupOption);
        command.Options.Add(installDirOption);
        command.Options.Add(binDirOption);
        command.Options.Add(channelOption);
        command.Options.Add(verboseOption);

        command.SetAction((parseResult, cancellationToken) =>
            runtime.RunInstallAsync(
                new InstallCommandOptions(
                    Local: parseResult.GetValue(localOption),
                    Yes: parseResult.GetValue(yesOption),
                    NoSetup: parseResult.GetValue(noSetupOption),
                    InstallDir: parseResult.GetValue(installDirOption),
                    BinDir: parseResult.GetValue(binDirOption),
                    Channel: parseResult.GetValue(channelOption),
                    Verbose: parseResult.GetValue(verboseOption)),
                cancellationToken));

        return command;
    }
}
