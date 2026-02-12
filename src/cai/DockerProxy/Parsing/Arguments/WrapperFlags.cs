using ContainAI.Cli.Host.DockerProxy.Models;

namespace ContainAI.Cli.Host.DockerProxy.Parsing.Arguments;

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
