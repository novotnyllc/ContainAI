using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static partial class RuntimeCommandsBuilder
{
    internal static Command CreateDockerCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("docker", "Run Docker in the ContainAI runtime context.")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var dockerArgs = new Argument<string[]>("docker-args")
        {
            Arity = ArgumentArity.ZeroOrMore,
            Description = "Arguments forwarded to docker.",
        };
        dockerArgs.CompletionSources.Add(DockerCompletionTokens);

        command.Arguments.Add(dockerArgs);
        command.SetAction((parseResult, cancellationToken) => runtime.RunDockerAsync(
            new DockerCommandOptions(RootCommandBuilder.BuildArgumentList(parseResult.GetValue(dockerArgs), parseResult.UnmatchedTokens)),
            cancellationToken));

        return command;
    }

    internal static Command CreateStatusCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("status", "Show runtime container status.");

        var jsonOption = new Option<bool>("--json")
        {
            Description = "Emit status as JSON lines.",
        };
        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path used for status resolution.",
        };
        var containerOption = new Option<string?>("--container")
        {
            Description = "Filter status output by container name.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };

        command.Options.Add(jsonOption);
        command.Options.Add(workspaceOption);
        command.Options.Add(containerOption);
        command.Options.Add(verboseOption);

        command.SetAction((parseResult, cancellationToken) => runtime.RunStatusAsync(
            new StatusCommandOptions(
                Json: parseResult.GetValue(jsonOption),
                Workspace: parseResult.GetValue(workspaceOption),
                Container: parseResult.GetValue(containerOption),
                Verbose: parseResult.GetValue(verboseOption)),
            cancellationToken));

        return command;
    }
}
