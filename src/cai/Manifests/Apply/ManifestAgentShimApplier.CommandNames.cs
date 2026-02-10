namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed partial class ManifestAgentShimApplier
{
    private static HashSet<string> BuildCommandNames(ManifestAgentEntry agent)
    {
        var names = new HashSet<string>(StringComparer.Ordinal)
        {
            agent.Name,
            agent.Binary,
        };
        foreach (var alias in agent.Aliases)
        {
            names.Add(alias);
        }

        return names;
    }

    private static void ValidateCommandName(string commandName, string sourceFile)
    {
        if (!ManifestAgentShimRegex.CommandName().IsMatch(commandName))
        {
            throw new InvalidOperationException($"invalid agent command name '{commandName}' in {sourceFile}");
        }
    }
}
