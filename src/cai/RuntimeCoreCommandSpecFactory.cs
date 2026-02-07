using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal static class RuntimeCoreCommandSpecFactory
{
    public static ProcessExecutionSpec CreateRunSpec(RunCommandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var arguments = new List<string>();
        AppendOption(arguments, "--credentials", options.Credentials);
        AppendFlag(arguments, "--acknowledge-credential-risk", options.AcknowledgeCredentialRisk);
        AppendOption(arguments, "--data-volume", options.DataVolume);
        AppendOption(arguments, "--config", options.Config);
        AppendOption(arguments, "--container", options.Container);
        AppendFlag(arguments, "--fresh", options.Fresh);
        AppendFlag(arguments, "--detached", options.Detached);
        AppendFlag(arguments, "--force", options.Force);
        AppendFlag(arguments, "--debug", options.Debug);
        AppendFlag(arguments, "--dry-run", options.DryRun);
        AppendOption(arguments, "--image-tag", options.ImageTag);
        AppendOption(arguments, "--template", options.Template);
        AppendOption(arguments, "--channel", options.Channel);
        AppendOption(arguments, "--memory", options.Memory);
        AppendOption(arguments, "--cpus", options.Cpus);
        foreach (var env in options.Env)
        {
            arguments.Add("--env");
            arguments.Add(env);
        }

        AppendLoginShellCommand(arguments, options.CommandArgs);

        return new ProcessExecutionSpec(
            FileName: "bash",
            Arguments: arguments,
            EnvironmentOverrides: CreateRuntimeEnvironment(
                workspace: options.Workspace,
                quiet: options.Quiet,
                verbose: options.Verbose,
                ("CAI_FRESH", options.Fresh ? "1" : null),
                ("CAI_DETACHED", options.Detached ? "1" : null)));
    }

    public static ProcessExecutionSpec CreateShellSpec(ShellCommandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var arguments = new List<string>();
        AppendFlag(arguments, "--fresh", options.Fresh);
        AppendFlag(arguments, "--reset", options.Reset);
        AppendOption(arguments, "--data-volume", options.DataVolume);
        AppendOption(arguments, "--config", options.Config);
        AppendOption(arguments, "--container", options.Container);
        AppendFlag(arguments, "--force", options.Force);
        AppendFlag(arguments, "--debug", options.Debug);
        AppendFlag(arguments, "--dry-run", options.DryRun);
        AppendOption(arguments, "--image-tag", options.ImageTag);
        AppendOption(arguments, "--template", options.Template);
        AppendOption(arguments, "--channel", options.Channel);
        AppendOption(arguments, "--memory", options.Memory);
        AppendOption(arguments, "--cpus", options.Cpus);
        AppendLoginShellCommand(arguments, options.CommandArgs);

        return new ProcessExecutionSpec(
            FileName: "bash",
            Arguments: arguments,
            EnvironmentOverrides: CreateRuntimeEnvironment(
                workspace: options.Workspace,
                quiet: options.Quiet,
                verbose: options.Verbose));
    }

    public static ProcessExecutionSpec CreateExecSpec(ExecCommandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var arguments = new List<string>();
        if (options.Quiet)
        {
            arguments.Add("-q");
        }

        if (options.Verbose)
        {
            arguments.Add("-v");
        }

        AppendOption(arguments, "--container", options.Container);
        AppendOption(arguments, "--template", options.Template);
        AppendOption(arguments, "--channel", options.Channel);
        AppendOption(arguments, "--data-volume", options.DataVolume);
        AppendOption(arguments, "--config", options.Config);
        AppendFlag(arguments, "--fresh", options.Fresh);
        AppendFlag(arguments, "--force", options.Force);
        AppendFlag(arguments, "--debug", options.Debug);
        AppendArguments(arguments, options.CommandArgs);

        return new ProcessExecutionSpec(
            FileName: "ssh",
            Arguments: arguments,
            EnvironmentOverrides: CreateRuntimeEnvironment(
                workspace: options.Workspace,
                quiet: options.Quiet,
                verbose: options.Verbose));
    }

    public static DockerExecutionSpec CreateDockerSpec(DockerCommandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        return new DockerExecutionSpec(Arguments: options.DockerArgs.ToArray());
    }

    public static DockerExecutionSpec CreateStatusSpec(StatusCommandOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        var arguments = new List<string>(capacity: 8)
        {
            "ps",
            "--filter",
            "label=containai.managed=true",
        };

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            arguments.Add("--filter");
            arguments.Add($"name={options.Container}");
        }

        if (options.Json)
        {
            arguments.Add("--format");
            arguments.Add("{{json .}}");
        }
        else if (options.Verbose)
        {
            arguments.Add("--no-trunc");
        }

        return new DockerExecutionSpec(Arguments: arguments);
    }

    private static void AppendLoginShellCommand(List<string> arguments, IReadOnlyList<string> commandArgs)
    {
        if (commandArgs.Count == 0)
        {
            arguments.Add("-l");
            return;
        }

        arguments.Add("-lc");
        arguments.Add(JoinForBash(commandArgs));
    }

    private static void AppendArguments(List<string> destination, IReadOnlyList<string> source)
    {
        foreach (var arg in source)
        {
            destination.Add(arg);
        }
    }

    private static void AppendOption(List<string> destination, string name, string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        destination.Add(name);
        destination.Add(value);
    }

    private static void AppendFlag(List<string> destination, string name, bool enabled)
    {
        if (enabled)
        {
            destination.Add(name);
        }
    }

    private static IReadOnlyDictionary<string, string?> CreateRuntimeEnvironment(
        string? workspace,
        bool quiet,
        bool verbose,
        params (string Key, string? Value)[] additionalValues)
    {
        var environment = new Dictionary<string, string?>(StringComparer.Ordinal)
        {
            ["CAI_WORKSPACE"] = workspace,
            ["CAI_QUIET"] = quiet ? "1" : null,
            ["CAI_VERBOSE"] = verbose ? "1" : null,
        };

        foreach (var (key, value) in additionalValues)
        {
            environment[key] = value;
        }

        return environment;
    }

    private static string JoinForBash(IReadOnlyList<string> commandArgs)
    {
        if (commandArgs.Count == 0)
        {
            return string.Empty;
        }

        var escaped = new string[commandArgs.Count];
        for (var index = 0; index < commandArgs.Count; index++)
        {
            escaped[index] = EscapeBashArgument(commandArgs[index]);
        }

        return string.Join(" ", escaped);
    }

    private static string EscapeBashArgument(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return "''";
        }

        return $"'{value.Replace("'", "'\"'\"'", StringComparison.Ordinal)}'";
    }
}
