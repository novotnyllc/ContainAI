using System.CommandLine;
using System.Reflection;
using System.Text.Encodings.Web;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

internal sealed class RootCommandBuilder
{
    private readonly AcpCommandBuilder _acpCommandBuilder;

    public RootCommandBuilder(AcpCommandBuilder? acpCommandBuilder = null)
    {
        _acpCommandBuilder = acpCommandBuilder ?? new AcpCommandBuilder();
    }

    public RootCommand Build(ICaiCommandRuntime runtime)
    {
        ArgumentNullException.ThrowIfNull(runtime);

        var root = new RootCommand("ContainAI native CLI")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        root.SetAction((_, cancellationToken) => runtime.RunRunAsync(
            new RunCommandOptions(
                Workspace: null,
                Fresh: false,
                Detached: false,
                Quiet: false,
                Verbose: false,
                AdditionalArgs: Array.Empty<string>(),
                CommandArgs: Array.Empty<string>()),
            cancellationToken));

        foreach (var name in CommandCatalog.RoutedCommandOrder.Where(static command => command != "acp"))
        {
            var command = name switch
            {
                "docker" => CreateDockerCommand(runtime),
                "status" => CreateStatusCommand(runtime),
                "version" => CreateVersionCommand(runtime),
                _ => CreateNativePassThroughCommand(name, runtime),
            };

            root.Subcommands.Add(command);
        }

        root.Subcommands.Add(_acpCommandBuilder.Build(runtime));

        return root;
    }

    private static Command CreateRunCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("run", "Start or attach to a runtime shell.")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for command execution.",
        };
        var freshOption = new Option<bool>("--fresh")
        {
            Description = "Request a fresh runtime environment.",
        };
        var detachedOption = new Option<bool>("--detached", "-d")
        {
            Description = "Run in detached mode.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.ZeroOrMore,
            Description = "Optional command to execute in the login shell.",
        };

        command.Options.Add(workspaceOption);
        command.Options.Add(freshOption);
        command.Options.Add(detachedOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) => runtime.RunRunAsync(
            new RunCommandOptions(
                Workspace: parseResult.GetValue(workspaceOption),
                Fresh: parseResult.GetValue(freshOption),
                Detached: parseResult.GetValue(detachedOption),
                Quiet: parseResult.GetValue(quietOption),
                Verbose: parseResult.GetValue(verboseOption),
                AdditionalArgs: parseResult.UnmatchedTokens.ToArray(),
                CommandArgs: parseResult.GetValue(commandArgs) ?? Array.Empty<string>()),
            cancellationToken));

        return command;
    }

    private static Command CreateShellCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("shell", "Open an interactive login shell.")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for shell execution.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.ZeroOrMore,
            Description = "Optional command to execute in the login shell.",
        };

        command.Options.Add(workspaceOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) => runtime.RunShellAsync(
            new ShellCommandOptions(
                Workspace: parseResult.GetValue(workspaceOption),
                Quiet: parseResult.GetValue(quietOption),
                Verbose: parseResult.GetValue(verboseOption),
                AdditionalArgs: parseResult.UnmatchedTokens.ToArray(),
                CommandArgs: parseResult.GetValue(commandArgs) ?? Array.Empty<string>()),
            cancellationToken));

        return command;
    }

    private static Command CreateExecCommand(ICaiCommandRuntime runtime)
    {
        var command = new Command("exec", "Execute a command through SSH.")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var workspaceOption = new Option<string?>("--workspace", "-w")
        {
            Description = "Workspace path for command execution.",
        };
        var quietOption = new Option<bool>("--quiet", "-q")
        {
            Description = "Suppress non-essential output.",
        };
        var verboseOption = new Option<bool>("--verbose")
        {
            Description = "Enable verbose output.",
        };
        var commandArgs = new Argument<string[]>("command")
        {
            Arity = ArgumentArity.ZeroOrMore,
            Description = "Command and arguments passed to ssh.",
        };

        command.Options.Add(workspaceOption);
        command.Options.Add(quietOption);
        command.Options.Add(verboseOption);
        command.Arguments.Add(commandArgs);

        command.SetAction((parseResult, cancellationToken) => runtime.RunExecAsync(
            new ExecCommandOptions(
                Workspace: parseResult.GetValue(workspaceOption),
                Quiet: parseResult.GetValue(quietOption),
                Verbose: parseResult.GetValue(verboseOption),
                AdditionalArgs: parseResult.UnmatchedTokens.ToArray(),
                CommandArgs: parseResult.GetValue(commandArgs) ?? Array.Empty<string>()),
            cancellationToken));

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
        var command = new Command("status", "Show runtime container status.")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

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
                Verbose: parseResult.GetValue(verboseOption),
                AdditionalArgs: parseResult.UnmatchedTokens.ToArray()),
            cancellationToken));

        return command;
    }

    private static IReadOnlyList<string> BuildArgumentList(string[]? parsedArgs, IReadOnlyList<string> unmatchedTokens)
    {
        if ((parsedArgs is null || parsedArgs.Length == 0) && unmatchedTokens.Count == 0)
        {
            return Array.Empty<string>();
        }

        var all = new List<string>(
            capacity: (parsedArgs?.Length ?? 0) + unmatchedTokens.Count);

        if (parsedArgs is not null && parsedArgs.Length > 0)
        {
            all.AddRange(parsedArgs);
        }

        if (unmatchedTokens.Count > 0)
        {
            all.AddRange(unmatchedTokens);
        }

        return all;
    }

    private static Command CreateNativePassThroughCommand(string commandName, ICaiCommandRuntime runtime)
    {
        var command = new Command(commandName)
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        command.SetAction((parseResult, cancellationToken) =>
        {
            var forwarded = new List<string>(capacity: parseResult.UnmatchedTokens.Count + 1)
            {
                commandName,
            };

            forwarded.AddRange(parseResult.UnmatchedTokens);
            return runtime.RunNativeAsync(forwarded, cancellationToken);
        });

        return command;
    }

    private static Command CreateVersionCommand(ICaiCommandRuntime runtime)
    {
        var versionCommand = new Command("version")
        {
            TreatUnmatchedTokensAsErrors = false,
        };

        var jsonOption = new Option<bool>("--json")
        {
            Description = "Emit version information as JSON.",
        };
        versionCommand.Options.Add(jsonOption);

        versionCommand.SetAction((parseResult, cancellationToken) =>
        {
            var useNativeJson = parseResult.GetValue(jsonOption) && parseResult.UnmatchedTokens.Count == 0;
            if (useNativeJson)
            {
                cancellationToken.ThrowIfCancellationRequested();
                Console.Out.WriteLine(GetVersionJson());
                return Task.FromResult(0);
            }

            var forwarded = new List<string>(capacity: parseResult.UnmatchedTokens.Count + 2)
            {
                "version",
            };

            if (parseResult.GetValue(jsonOption))
            {
                forwarded.Add("--json");
            }

            forwarded.AddRange(parseResult.UnmatchedTokens);
            return runtime.RunNativeAsync(forwarded, cancellationToken);
        });

        return versionCommand;
    }

    internal static string GetVersionJson()
    {
        var installDir = ResolveInstallDirectory();
        var version = ResolveVersion(installDir);
        var installType = ResolveInstallType(installDir);

        return $"{{\"version\":\"{JavaScriptEncoder.Default.Encode(version)}\",\"install_type\":\"{JavaScriptEncoder.Default.Encode(installType)}\",\"install_dir\":\"{JavaScriptEncoder.Default.Encode(installDir)}\"}}";
    }

    private static string ResolveVersion(string installDir)
    {
        var versionFile = Path.Combine(installDir, "VERSION");
        if (File.Exists(versionFile))
        {
            var value = File.ReadAllText(versionFile).Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString()
            ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString();

        return string.IsNullOrWhiteSpace(assemblyVersion) ? "0.0.0" : assemblyVersion;
    }

    private static string ResolveInstallType(string installDir)
    {
        if (Directory.Exists(Path.Combine(installDir, ".git")))
        {
            return "git";
        }

        var normalized = installDir.Replace('\\', '/');
        if (normalized.Contains("/.local/share/containai", StringComparison.Ordinal))
        {
            return "local";
        }

        return "installed";
    }

    private static string ResolveInstallDirectory()
    {
        foreach (var candidate in EnumerateInstallDirectoryCandidates())
        {
            if (File.Exists(Path.Combine(candidate, "VERSION")))
            {
                return candidate;
            }
        }

        return Directory.GetCurrentDirectory();
    }

    private static IEnumerable<string> EnumerateInstallDirectoryCandidates()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var root in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var current = Path.GetFullPath(root);
            while (!string.IsNullOrWhiteSpace(current))
            {
                if (seen.Add(current))
                {
                    yield return current;
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }
    }
}
