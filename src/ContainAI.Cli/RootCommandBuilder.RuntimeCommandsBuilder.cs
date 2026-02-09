using System.CommandLine;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal static class RuntimeCommandsBuilder
{
    private static readonly string[] DockerCompletionTokens =
    [
        "attach",
        "build",
        "buildx",
        "commit",
        "compose",
        "container",
        "context",
        "cp",
        "create",
        "exec",
        "image",
        "images",
        "info",
        "inspect",
        "kill",
        "load",
        "login",
        "logout",
        "logs",
        "network",
        "pause",
        "port",
        "ps",
        "pull",
        "push",
        "rename",
        "restart",
        "rm",
        "rmi",
        "run",
        "save",
        "search",
        "start",
        "stats",
        "stop",
        "system",
        "tag",
        "top",
        "unpause",
        "update",
        "version",
        "volume",
        "wait",
    ];

    internal static Command CreateRunCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("run", "Start or attach to a runtime shell.");

        var workspaceOption = CreateWorkspaceOption("Workspace path for command execution.");
        var freshOption = CreateFreshOption();
        var restartOption = CreateRestartOption();
        var detachedOption = new Option<bool>("--detached", "-d")
        {
            Description = "Run in detached mode.",
        };
        var credentialsOption = new Option<string?>("--credentials")
        {
            Description = "Credential mode (for example: copy).",
        };
        var acknowledgeCredentialRiskOption = new Option<bool>("--acknowledge-credential-risk")
        {
            Description = "Acknowledge credential risk for credential import modes.",
        };
        var dataVolumeOption = CreateDataVolumeOption();
        var configOption = CreateConfigOption();
        var containerOption = CreateContainerOption();
        var forceOption = CreateForceOption();
        var quietOption = CreateQuietOption();
        var verboseOption = CreateVerboseOption();
        var debugOption = CreateDebugOption();
        var dryRunOption = CreateDryRunOption();
        var imageTagOption = new Option<string?>("--image-tag")
        {
            Description = "Override image tag.",
        };
        var templateOption = CreateTemplateOption();
        var channelOption = CreateChannelOption();
        var memoryOption = CreateMemoryOption();
        var cpusOption = CreateCpusOption();
        var envOption = new Option<string[]>("--env", "-e")
        {
            Description = "Environment variable assignment.",
            AllowMultipleArgumentsPerToken = false,
        };
        var pathArgument = new Argument<string?>("path")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Workspace path (optional positional form).",
        };
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.ZeroOrMore,
            Description = "Optional command to execute in the login shell.",
        };

        AddOptions(
            command,
            workspaceOption,
            freshOption,
            restartOption,
            detachedOption,
            credentialsOption,
            acknowledgeCredentialRiskOption,
            dataVolumeOption,
            configOption,
            containerOption,
            forceOption,
            quietOption,
            verboseOption,
            debugOption,
            dryRunOption,
            imageTagOption,
            templateOption,
            channelOption,
            memoryOption,
            cpusOption,
            envOption);
        command.Arguments.Add(pathArgument);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) =>
        {
            var commandArguments = parseResult.GetValue(commandArgs) ?? Array.Empty<string>();

            var workspace = parseResult.GetValue(workspaceOption);
            var positionalPath = parseResult.GetValue(pathArgument);
            if (string.IsNullOrWhiteSpace(workspace) && !string.IsNullOrWhiteSpace(positionalPath))
            {
                if (Directory.Exists(RootCommandBuilder.ExpandHome(positionalPath)))
                {
                    workspace = positionalPath;
                }
                else
                {
                    commandArguments = [positionalPath, .. commandArguments];
                }
            }

            return runtime.RunRunAsync(
                new RunCommandOptions(
                    Workspace: workspace,
                    Fresh: parseResult.GetValue(freshOption) || parseResult.GetValue(restartOption),
                    Detached: parseResult.GetValue(detachedOption),
                    Quiet: parseResult.GetValue(quietOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    Credentials: parseResult.GetValue(credentialsOption),
                    AcknowledgeCredentialRisk: parseResult.GetValue(acknowledgeCredentialRiskOption),
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Config: parseResult.GetValue(configOption),
                    Container: parseResult.GetValue(containerOption),
                    Force: parseResult.GetValue(forceOption),
                    Debug: parseResult.GetValue(debugOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    ImageTag: parseResult.GetValue(imageTagOption),
                    Template: parseResult.GetValue(templateOption),
                    Channel: parseResult.GetValue(channelOption),
                    Memory: parseResult.GetValue(memoryOption),
                    Cpus: parseResult.GetValue(cpusOption),
                    Env: parseResult.GetValue(envOption)?
                        .Where(static value => !string.IsNullOrWhiteSpace(value))
                        .ToArray() ?? Array.Empty<string>(),
                    CommandArgs: commandArguments),
                cancellationToken);
        });

        return command;
    }

    internal static Command CreateShellCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("shell", "Open an interactive login shell.");

        var workspaceOption = CreateWorkspaceOption("Workspace path for shell execution.");
        var dataVolumeOption = CreateDataVolumeOption();
        var configOption = CreateConfigOption();
        var containerOption = CreateContainerOption();
        var freshOption = CreateFreshOption();
        var restartOption = CreateRestartOption();
        var resetOption = new Option<bool>("--reset")
        {
            Description = "Create a reset volume shell session.",
        };
        var forceOption = CreateForceOption();
        var quietOption = CreateQuietOption();
        var verboseOption = CreateVerboseOption();
        var debugOption = CreateDebugOption();
        var dryRunOption = CreateDryRunOption();
        var imageTagOption = new Option<string?>("--image-tag")
        {
            Description = "Override image tag.",
        };
        var templateOption = CreateTemplateOption();
        var channelOption = CreateChannelOption();
        var memoryOption = CreateMemoryOption();
        var cpusOption = CreateCpusOption();
        var pathArgument = new Argument<string?>("path")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Workspace path (optional positional form).",
        };

        AddOptions(
            command,
            workspaceOption,
            dataVolumeOption,
            configOption,
            containerOption,
            freshOption,
            restartOption,
            resetOption,
            forceOption,
            quietOption,
            verboseOption,
            debugOption,
            dryRunOption,
            imageTagOption,
            templateOption,
            channelOption,
            memoryOption,
            cpusOption);
        command.Arguments.Add(pathArgument);

        command.SetAction((parseResult, cancellationToken) =>
        {
            var workspace = parseResult.GetValue(workspaceOption);
            var positionalPath = parseResult.GetValue(pathArgument);
            if (string.IsNullOrWhiteSpace(workspace) && !string.IsNullOrWhiteSpace(positionalPath))
            {
                workspace = positionalPath;
            }

            return runtime.RunShellAsync(
                new ShellCommandOptions(
                    Workspace: workspace,
                    Fresh: parseResult.GetValue(freshOption) || parseResult.GetValue(restartOption),
                    Reset: parseResult.GetValue(resetOption),
                    Quiet: parseResult.GetValue(quietOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Config: parseResult.GetValue(configOption),
                    Container: parseResult.GetValue(containerOption),
                    Force: parseResult.GetValue(forceOption),
                    Debug: parseResult.GetValue(debugOption),
                    DryRun: parseResult.GetValue(dryRunOption),
                    ImageTag: parseResult.GetValue(imageTagOption),
                    Template: parseResult.GetValue(templateOption),
                    Channel: parseResult.GetValue(channelOption),
                    Memory: parseResult.GetValue(memoryOption),
                    Cpus: parseResult.GetValue(cpusOption),
                    CommandArgs: Array.Empty<string>()),
                cancellationToken);
        });

        return command;
    }

    internal static Command CreateExecCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("exec", "Execute a command through SSH.");

        var workspaceOption = CreateWorkspaceOption("Workspace path for command execution.");
        var containerOption = CreateContainerOption();
        var templateOption = CreateTemplateOption();
        var channelOption = CreateChannelOption();
        var dataVolumeOption = CreateDataVolumeOption();
        var configOption = CreateConfigOption();
        var freshOption = CreateFreshOption();
        var forceOption = CreateForceOption();
        var quietOption = CreateQuietOption();
        var verboseOption = CreateVerboseOption();
        var debugOption = CreateDebugOption();
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.OneOrMore,
            Description = "Command and arguments passed to ssh.",
        };

        AddOptions(
            command,
            workspaceOption,
            containerOption,
            templateOption,
            channelOption,
            dataVolumeOption,
            configOption,
            freshOption,
            forceOption,
            quietOption,
            verboseOption,
            debugOption);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) =>
        {
            return runtime.RunExecAsync(
                new ExecCommandOptions(
                    Workspace: parseResult.GetValue(workspaceOption),
                    Quiet: parseResult.GetValue(quietOption),
                    Verbose: parseResult.GetValue(verboseOption),
                    Container: parseResult.GetValue(containerOption),
                    Template: parseResult.GetValue(templateOption),
                    Channel: parseResult.GetValue(channelOption),
                    DataVolume: parseResult.GetValue(dataVolumeOption),
                    Config: parseResult.GetValue(configOption),
                    Fresh: parseResult.GetValue(freshOption),
                    Force: parseResult.GetValue(forceOption),
                    Debug: parseResult.GetValue(debugOption),
                    CommandArgs: parseResult.GetValue(commandArgs) ?? Array.Empty<string>()),
                cancellationToken);
        });

        return command;
    }

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

    private static void AddOptions(Command command, params Option[] options)
    {
        foreach (var option in options)
        {
            command.Options.Add(option);
        }
    }

    private static Option<string?> CreateWorkspaceOption(string description)
        => new("--workspace", "-w")
        {
            Description = description,
        };

    private static Option<bool> CreateFreshOption()
        => new("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };

    private static Option<bool> CreateRestartOption()
        => new("--restart")
        {
            Description = "Alias for --fresh.",
        };

    private static Option<string?> CreateDataVolumeOption()
        => new("--data-volume")
        {
            Description = "Data volume override.",
        };

    private static Option<string?> CreateConfigOption()
        => new("--config")
        {
            Description = "Path to config file.",
        };

    private static Option<string?> CreateContainerOption()
        => new("--container")
        {
            Description = "Attach to a specific container.",
        };

    private static Option<bool> CreateForceOption()
        => new("--force")
        {
            Description = "Force operation where supported.",
        };

    private static Option<bool> CreateQuietOption()
        => new("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };

    private static Option<bool> CreateVerboseOption()
        => new("--verbose")
        {
            Description = "Enable verbose output.",
        };

    private static Option<bool> CreateDebugOption()
        => new("--debug", "-D")
        {
            Description = "Enable debug output.",
        };

    private static Option<bool> CreateDryRunOption()
        => new("--dry-run")
        {
            Description = "Show planned actions without executing.",
        };

    private static Option<string?> CreateTemplateOption()
        => new("--template")
        {
            Description = "Template name.",
        };

    private static Option<string?> CreateChannelOption()
        => new("--channel")
        {
            Description = "Channel override.",
        };

    private static Option<string?> CreateMemoryOption()
        => new("--memory")
        {
            Description = "Container memory limit.",
        };

    private static Option<string?> CreateCpusOption()
        => new("--cpus")
        {
            Description = "Container CPU limit.",
        };
}
