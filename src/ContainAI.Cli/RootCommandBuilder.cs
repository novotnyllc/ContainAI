using System.CommandLine;
using System.CommandLine.Parsing;
using System.Text.Encodings.Web;
using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host;

namespace ContainAI.Cli;

internal static partial class RootCommandBuilder
{
    public static RootCommand Build(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);

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

        foreach (var name in CommandCatalog.RoutedCommandOrder)
        {
            var command = name switch
            {
                "run" => CreateRunCommand(runtime),
                "shell" => CreateShellCommand(runtime),
                "exec" => CreateExecCommand(runtime),
                "doctor" => CreateDoctorCommand(runtime),
                "setup" => CreateSetupCommand(runtime),
                "validate" => CreateValidateCommand(runtime),
                "docker" => CreateDockerCommand(runtime),
                "import" => CreateImportCommand(runtime),
                "export" => CreateExportCommand(runtime),
                "sync" => CreateSyncCommand(runtime),
                "stop" => CreateStopCommand(runtime),
                "status" => CreateStatusCommand(runtime),
                "gc" => CreateGcCommand(runtime),
                "ssh" => CreateSshCommand(runtime),
                "links" => CreateLinksCommand(runtime),
                "config" => CreateConfigCommand(runtime),
                "manifest" => CreateManifestCommand(runtime),
                "template" => CreateTemplateCommand(runtime),
                "update" => CreateUpdateCommand(runtime),
                "refresh" => CreateRefreshCommand(runtime),
                "uninstall" => CreateUninstallCommand(runtime),
                "help" => CreateHelpCommand(runtime),
                "system" => CreateSystemCommand(runtime),
                "completion" => CreateCompletionCommand(root),
                "version" => CreateVersionCommand(runtime),
                "acp" => AcpCommandBuilder.Build(runtime),
                _ => throw new InvalidOperationException($"Unsupported routed command '{name}'."),
            };

            root.Subcommands.Add(command);
        }

        return root;
    }

    private static Command CreateRunCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("run", "Start or attach to a runtime shell.");

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for command execution.",
        };
        var freshOption = new Option<bool>("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };
        var restartOption = new Option<bool>("--restart")
        {
            Description = "Alias for --fresh.",
        };
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
        var dataVolumeOption = new Option<string?>("--data-volume")
        {
            Description = "Data volume override.",
        };
        var configOption = new Option<string?>("--config")
        {
            Description = "Path to config file.",
        };
        var containerOption = new Option<string?>("--container")
        {
            Description = "Attach to a specific container.",
        };
        var forceOption = new Option<bool>("--force")
        {
            Description = "Force operation where supported.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var debugOption = new Option<bool>("--debug", "-D")
        {
            Description = "Enable debug output.",
        };
        var dryRunOption = new Option<bool>("--dry-run")
        {
            Description = "Show planned actions without executing.",
        };
        var imageTagOption = new Option<string?>("--image-tag")
        {
            Description = "Override image tag.",
        };
        var templateOption = new Option<string?>("--template")
        {
            Description = "Template name.",
        };
        var channelOption = new Option<string?>("--channel")
        {
            Description = "Channel override.",
        };
        var memoryOption = new Option<string?>("--memory")
        {
            Description = "Container memory limit.",
        };
        var cpusOption = new Option<string?>("--cpus")
        {
            Description = "Container CPU limit.",
        };
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

        command.Options.Add(workspaceOption);
        command.Options.Add(freshOption);
        command.Options.Add(restartOption);
        command.Options.Add(detachedOption);
        command.Options.Add(credentialsOption);
        command.Options.Add(acknowledgeCredentialRiskOption);
        command.Options.Add(dataVolumeOption);
        command.Options.Add(configOption);
        command.Options.Add(containerOption);
        command.Options.Add(forceOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Options.Add(debugOption);
        command.Options.Add(dryRunOption);
        command.Options.Add(imageTagOption);
        command.Options.Add(templateOption);
        command.Options.Add(channelOption);
        command.Options.Add(memoryOption);
        command.Options.Add(cpusOption);
        command.Options.Add(envOption);
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

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for shell execution.",
        };
        var dataVolumeOption = new Option<string?>("--data-volume")
        {
            Description = "Data volume override.",
        };
        var configOption = new Option<string?>("--config")
        {
            Description = "Path to config file.",
        };
        var containerOption = new Option<string?>("--container")
        {
            Description = "Attach to a specific container.",
        };
        var freshOption = new Option<bool>("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };
        var restartOption = new Option<bool>("--restart")
        {
            Description = "Alias for --fresh.",
        };
        var resetOption = new Option<bool>("--reset")
        {
            Description = "Create a reset volume shell session.",
        };
        var forceOption = new Option<bool>("--force")
        {
            Description = "Force operation where supported.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var debugOption = new Option<bool>("--debug", "-D")
        {
            Description = "Enable debug output.",
        };
        var dryRunOption = new Option<bool>("--dry-run")
        {
            Description = "Show planned actions without executing.",
        };
        var imageTagOption = new Option<string?>("--image-tag")
        {
            Description = "Override image tag.",
        };
        var templateOption = new Option<string?>("--template")
        {
            Description = "Template name.",
        };
        var channelOption = new Option<string?>("--channel")
        {
            Description = "Channel override.",
        };
        var memoryOption = new Option<string?>("--memory")
        {
            Description = "Container memory limit.",
        };
        var cpusOption = new Option<string?>("--cpus")
        {
            Description = "Container CPU limit.",
        };
        var pathArgument = new Argument<string?>("path")
        {
            Arity = ArgumentArity.ZeroOrOne,
            Description = "Workspace path (optional positional form).",
        };

        command.Options.Add(workspaceOption);
        command.Options.Add(dataVolumeOption);
        command.Options.Add(configOption);
        command.Options.Add(containerOption);
        command.Options.Add(freshOption);
        command.Options.Add(restartOption);
        command.Options.Add(resetOption);
        command.Options.Add(forceOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Options.Add(debugOption);
        command.Options.Add(dryRunOption);
        command.Options.Add(imageTagOption);
        command.Options.Add(templateOption);
        command.Options.Add(channelOption);
        command.Options.Add(memoryOption);
        command.Options.Add(cpusOption);
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

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for command execution.",
        };
        var containerOption = new Option<string?>("--container")
        {
            Description = "Attach to a specific container.",
        };
        var templateOption = new Option<string?>("--template")
        {
            Description = "Template name.",
        };
        var channelOption = new Option<string?>("--channel")
        {
            Description = "Channel override.",
        };
        var dataVolumeOption = new Option<string?>("--data-volume")
        {
            Description = "Data volume override.",
        };
        var configOption = new Option<string?>("--config")
        {
            Description = "Path to config file.",
        };
        var freshOption = new Option<bool>("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };
        var forceOption = new Option<bool>("--force")
        {
            Description = "Force operation where supported.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var debugOption = new Option<bool>("--debug", "-D")
        {
            Description = "Enable debug output.",
        };
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.OneOrMore,
            Description = "Command and arguments passed to ssh.",
        };

        command.Options.Add(workspaceOption);
        command.Options.Add(containerOption);
        command.Options.Add(templateOption);
        command.Options.Add(channelOption);
        command.Options.Add(dataVolumeOption);
        command.Options.Add(configOption);
        command.Options.Add(freshOption);
        command.Options.Add(forceOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Options.Add(debugOption);
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

    private static Command CreateCompletionCommand(RootCommand root)
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
            var completionArgs = NormalizeCompletionArguments(normalized.Line);
            var completionResult = CommandLineParser.Parse(root, completionArgs, configuration: null);

            foreach (var completion in completionResult.GetCompletions(position: normalized.Cursor))
            {
                var value = string.IsNullOrWhiteSpace(completion.InsertText) ? completion.Label : completion.InsertText;
                if (string.IsNullOrWhiteSpace(value))
                {
                    continue;
                }

                await Console.Out.WriteLineAsync(value).ConfigureAwait(false);
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
        if (!string.Equals(Path.GetFileNameWithoutExtension(invocationToken), "cai", StringComparison.OrdinalIgnoreCase))
        {
            return (line, clampedPosition);
        }

        var trimStart = end;
        while (trimStart < line.Length && char.IsWhiteSpace(line[trimStart]))
        {
            trimStart++;
        }

        return (line[trimStart..], Math.Max(0, clampedPosition - trimStart));
    }

    private static string[] NormalizeCompletionArguments(string line)
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

        if (ShouldImplicitRunForCompletion(normalized))
        {
            return ["run", .. normalized];
        }

        return normalized;
    }

    private static bool ShouldImplicitRunForCompletion(string[] args)
    {
        if (args.Length == 0)
        {
            return false;
        }

        var firstToken = args[0];
        if (CommandCatalog.RootParserTokens.Contains(firstToken))
        {
            return false;
        }

        if (firstToken.StartsWith('-'))
        {
            return true;
        }

        if (CommandCatalog.RoutedCommands.Any(command => command.StartsWith(firstToken, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        return !CommandCatalog.RoutedCommands.Contains(firstToken);
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

        return path.Length == 1
            ? home!
            : Path.Combine(home!, path[2..]);
    }

    private static Command CreateVersionCommand(ICaiCommandRuntime runtime)
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
                await Console.Out.WriteLineAsync(GetVersionJson()).ConfigureAwait(false);
                return 0;
            }

            return await runtime.RunNativeAsync(["version"], cancellationToken).ConfigureAwait(false);
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
