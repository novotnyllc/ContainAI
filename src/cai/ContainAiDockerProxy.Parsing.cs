namespace ContainAI.Cli.Host;

internal interface IDockerProxyArgumentParser
{
    DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args);

    DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args);

    bool IsContainerCreateCommand(IReadOnlyList<string> args);

    string SanitizeWorkspaceName(string value);

    string? GetFirstSubcommand(IReadOnlyList<string> args);

    string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand);

    List<string> PrependContext(string contextName, IReadOnlyList<string> args);
}

internal interface IDevcontainerFeatureSettingsParser
{
    string StripJsoncComments(string content);

    bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings);

    bool IsValidVolumeName(string volume);
}

internal sealed class DockerProxyArgumentParser : IDockerProxyArgumentParser
{
    public DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count);
        var verbose = false;
        var quiet = false;

        foreach (var arg in args)
        {
            if (string.Equals(arg, "--verbose", StringComparison.Ordinal))
            {
                verbose = true;
                continue;
            }

            if (string.Equals(arg, "--quiet", StringComparison.Ordinal))
            {
                quiet = true;
                continue;
            }

            dockerArgs.Add(arg);
        }

        return new DockerProxyWrapperFlags(dockerArgs, verbose, quiet);
    }

    public DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args)
    {
        string? configFile = null;
        string? localFolder = null;

        for (var index = 0; index < args.Count; index++)
        {
            var token = args[index];
            if (string.Equals(token, "--label", StringComparison.Ordinal) && index + 1 < args.Count)
            {
                ParseLabel(args[index + 1], ref configFile, ref localFolder);
                index++;
                continue;
            }

            if (token.StartsWith("--label=", StringComparison.Ordinal))
            {
                ParseLabel(token[8..], ref configFile, ref localFolder);
            }
        }

        return new DevcontainerLabels(configFile, localFolder);
    }

    public bool IsContainerCreateCommand(IReadOnlyList<string> args)
    {
        var firstToken = string.Empty;
        var secondToken = string.Empty;

        foreach (var arg in args)
        {
            if (arg.StartsWith('-'))
            {
                continue;
            }

            if (string.IsNullOrEmpty(firstToken))
            {
                firstToken = arg;
                continue;
            }

            secondToken = arg;
            break;
        }

        if (string.Equals(firstToken, "run", StringComparison.Ordinal) ||
            string.Equals(firstToken, "create", StringComparison.Ordinal))
        {
            return true;
        }

        return string.Equals(firstToken, "container", StringComparison.Ordinal) &&
               (string.Equals(secondToken, "run", StringComparison.Ordinal) ||
                string.Equals(secondToken, "create", StringComparison.Ordinal));
    }

    public string SanitizeWorkspaceName(string value) => DockerProxyValidationHelpers.SanitizeWorkspaceName(value);

    public string? GetFirstSubcommand(IReadOnlyList<string> args)
    {
        foreach (var arg in args)
        {
            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    public string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand)
    {
        var seenSubcommand = false;
        foreach (var arg in args)
        {
            if (!seenSubcommand)
            {
                if (string.Equals(arg, subcommand, StringComparison.Ordinal))
                {
                    seenSubcommand = true;
                }

                continue;
            }

            if (!arg.StartsWith('-'))
            {
                return arg;
            }
        }

        return null;
    }

    public List<string> PrependContext(string contextName, IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count + 2)
        {
            "--context",
            contextName,
        };

        dockerArgs.AddRange(args);
        return dockerArgs;
    }

    private static void ParseLabel(string labelToken, ref string? configFile, ref string? localFolder)
    {
        if (labelToken.StartsWith("devcontainer.config_file=", StringComparison.Ordinal))
        {
            configFile = labelToken[25..];
            return;
        }

        if (labelToken.StartsWith("devcontainer.local_folder=", StringComparison.Ordinal))
        {
            localFolder = labelToken[26..];
        }
    }
}

internal sealed class DevcontainerFeatureSettingsParser : IDevcontainerFeatureSettingsParser
{
    private readonly ContainAiDockerProxyOptions options;

    public DevcontainerFeatureSettingsParser(ContainAiDockerProxyOptions options) => this.options = options;

    public string StripJsoncComments(string content) => DockerProxyFeatureSettingsParsing.StripJsoncComments(content);

    public bool TryReadFeatureSettings(string configFile, TextWriter stderr, out FeatureSettings settings)
        => DockerProxyFeatureSettingsParsing.TryReadFeatureSettings(configFile, stderr, options, out settings);

    public bool IsValidVolumeName(string volume) => DockerProxyValidationHelpers.IsValidVolumeName(volume);
}

internal readonly record struct DockerProxyWrapperFlags(IReadOnlyList<string> DockerArgs, bool Verbose, bool Quiet);

internal readonly record struct DevcontainerLabels(string? ConfigFile, string? LocalFolder);

internal readonly record struct DockerProxyProcessResult(int ExitCode, string StandardOutput, string StandardError);

internal sealed record ContainAiDockerProxyOptions(string DefaultContext, string DefaultDataVolume, int SshPortRangeStart, int SshPortRangeEnd)
{
    public static ContainAiDockerProxyOptions Default { get; } = new("containai-docker", "containai-data", 2400, 2499);
}

internal readonly record struct FeatureSettings(bool HasContainAiFeature, string DataVolume, bool EnableCredentials, string RemoteUser)
{
    public static FeatureSettings Default(string defaultDataVolume) => new(false, defaultDataVolume, false, "vscode");
}
