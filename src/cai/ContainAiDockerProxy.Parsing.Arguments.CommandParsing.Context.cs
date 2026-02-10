namespace ContainAI.Cli.Host;

internal static partial class DockerProxyCommandParsing
{
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
