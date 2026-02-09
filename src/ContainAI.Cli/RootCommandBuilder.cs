using System.Collections.Frozen;
using System.CommandLine;
using System.CommandLine.Parsing;
using System.Text.Encodings.Web;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host;

namespace ContainAI.Cli;

internal static partial class RootCommandBuilder
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

    public static RootCommand Build(ICaiCommandRuntime runtime, ICaiConsole console)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentNullException.ThrowIfNull(console);

        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = true,
        };

        root.SetAction((_, cancellationToken) => runtime.RunRunAsync(
            new RunCommandOptions(
                Workspace: null,
                Fresh: false,
                Detached: false,
                Quiet: false,
                Verbose: false,
                Credentials: null,
                AcknowledgeCredentialRisk: false,
                DataVolume: null,
                Config: null,
                Container: null,
                Force: false,
                Debug: false,
                DryRun: false,
                ImageTag: null,
                Template: null,
                Channel: null,
                Memory: null,
                Cpus: null,
                Env: Array.Empty<string>(),
                CommandArgs: Array.Empty<string>()),
            cancellationToken));

        root.Subcommands.Add(CreateRunCommand(runtime));
        root.Subcommands.Add(CreateShellCommand(runtime));
        root.Subcommands.Add(CreateExecCommand(runtime));
        root.Subcommands.Add(CreateDoctorCommand(runtime));
        root.Subcommands.Add(CreateInstallCommand(runtime));
        root.Subcommands.Add(CreateExamplesCommand(runtime));
        root.Subcommands.Add(CreateSetupCommand(runtime));
        root.Subcommands.Add(CreateValidateCommand(runtime));
        root.Subcommands.Add(CreateDockerCommand(runtime));
        root.Subcommands.Add(CreateImportCommand(runtime));
        root.Subcommands.Add(CreateExportCommand(runtime));
        root.Subcommands.Add(CreateSyncCommand(runtime));
        root.Subcommands.Add(CreateStopCommand(runtime));
        root.Subcommands.Add(CreateStatusCommand(runtime));
        root.Subcommands.Add(CreateGcCommand(runtime));
        root.Subcommands.Add(CreateSshCommand(runtime));
        root.Subcommands.Add(CreateLinksCommand(runtime));
        root.Subcommands.Add(CreateConfigCommand(runtime));
        root.Subcommands.Add(CreateManifestCommand(runtime));
        root.Subcommands.Add(CreateTemplateCommand(runtime));
        root.Subcommands.Add(CreateUpdateCommand(runtime));
        root.Subcommands.Add(CreateRefreshCommand(runtime));
        root.Subcommands.Add(CreateUninstallCommand(runtime));
        root.Subcommands.Add(CreateCompletionCommand(root, console));
        root.Subcommands.Add(CreateVersionCommand(runtime, console));
        root.Subcommands.Add(CreateHelpCommand(runtime));
        root.Subcommands.Add(CreateSystemCommand(runtime));
        root.Subcommands.Add(AcpCommandBuilder.Build(runtime));

        return root;
    }

    private static Command CreateRunCommand(ICaiCommandRuntime runtime)
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
                if (Directory.Exists(ExpandHome(positionalPath)))
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

    private static Command CreateShellCommand(ICaiCommandRuntime runtime)
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

    private static Command CreateExecCommand(ICaiCommandRuntime runtime)
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

    private static Command CreateDockerCommand(ICaiCommandRuntime runtime)
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
            new DockerCommandOptions(BuildArgumentList(parseResult.GetValue(dockerArgs), parseResult.UnmatchedTokens)),
            cancellationToken));

        return command;
    }

    private static Command CreateStatusCommand(ICaiCommandRuntime runtime)
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

    private static string[] BuildArgumentList(string[]? parsedArgs, IReadOnlyList<string> unmatchedTokens)
        => (parsedArgs, unmatchedTokens.Count) switch
        {
            ({ Length: > 0 }, > 0) => [.. parsedArgs, .. unmatchedTokens],
            ({ Length: > 0 }, 0) => parsedArgs,
            (null or { Length: 0 }, > 0) => [.. unmatchedTokens],
            _ => Array.Empty<string>(),
        };

    private static Command CreateCompletionCommand(RootCommand root, ICaiConsole console)
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
            var normalized = NormalizeCompletionInput(line, requestedPosition);
            var knownCommands = root.Subcommands
                .Select(static command => command.Name)
                .ToFrozenSet(StringComparer.Ordinal);
            var completionArgs = NormalizeCompletionArguments(normalized.Line, knownCommands);
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

    private static (string Line, int Cursor) NormalizeCompletionInput(string line, int position)
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

    private static string[] NormalizeCompletionArguments(string line, FrozenSet<string> knownCommands)
    {
        var normalized = CommandLineParser.SplitCommandLine(line).ToArray();
        if (normalized.Length == 0)
        {
            return Array.Empty<string>();
        }

        normalized = normalized switch
        {
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
        if (firstToken is "help" or "--help" or "-h")
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

    private static string ExpandHome(string path)
    {
        if (!path.StartsWith('~'))
        {
            return path;
        }

        var home = Environment.GetEnvironmentVariable("HOME");
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        if (path.Length == 1)
        {
            return home!;
        }

        return path[1] is '/' or '\\'
            ? Path.Combine(home!, path[2..])
            : path;
    }

    private static Command CreateVersionCommand(ICaiCommandRuntime runtime, ICaiConsole console)
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
                await console.OutputWriter.WriteLineAsync(GetVersionJson()).ConfigureAwait(false);
                return 0;
            }

            return await runtime.RunVersionAsync(cancellationToken).ConfigureAwait(false);
        });

        return versionCommand;
    }

    internal static string GetVersionJson()
    {
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        return $"{{\"version\":\"{JavaScriptEncoder.Default.Encode(versionInfo.Version)}\",\"install_type\":\"{JavaScriptEncoder.Default.Encode(installType)}\",\"install_dir\":\"{JavaScriptEncoder.Default.Encode(versionInfo.InstallDir)}\"}}";
    }
}
