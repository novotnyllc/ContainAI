namespace ContainAI.Cli.Host;

internal static partial class AgentShimDispatcher
{
    private static List<string> ComposeCommandArguments(IReadOnlyList<string> defaultArgs, IReadOnlyList<string> args)
    {
        var commandArgs = new List<string>(defaultArgs.Count + args.Count);
        commandArgs.AddRange(defaultArgs);
        commandArgs.AddRange(args);
        return commandArgs;
    }
}
