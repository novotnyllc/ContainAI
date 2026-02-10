namespace ContainAI.Cli.Host;

internal static partial class DockerProxyCommandParsing
{
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
}
