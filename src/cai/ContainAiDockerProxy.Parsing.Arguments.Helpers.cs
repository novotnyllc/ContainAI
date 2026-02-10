namespace ContainAI.Cli.Host;

internal static class DockerProxyWrapperFlagParsing
{
    public static DockerProxyWrapperFlags ParseWrapperFlags(IReadOnlyList<string> args)
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
}

internal static class DockerProxyDevcontainerLabelParsing
{
    public static DevcontainerLabels ExtractDevcontainerLabels(IReadOnlyList<string> args)
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

internal static class DockerProxyCommandParsing
{
    public static bool IsContainerCreateCommand(IReadOnlyList<string> args)
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

    public static string? GetFirstSubcommand(IReadOnlyList<string> args)
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

    public static string? GetContainerNameArg(IReadOnlyList<string> args, string subcommand)
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

    public static List<string> PrependContext(string contextName, IReadOnlyList<string> args)
    {
        var dockerArgs = new List<string>(args.Count + 2)
        {
            "--context",
            contextName,
        };

        dockerArgs.AddRange(args);
        return dockerArgs;
    }
}
