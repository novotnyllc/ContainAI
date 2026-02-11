namespace ContainAI.Cli.Host;

internal static partial class DockerProxyCommandParsing
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
}
