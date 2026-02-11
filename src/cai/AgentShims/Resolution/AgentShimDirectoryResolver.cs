namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimDirectoryResolver
{
    string[] ResolveDirectories();
}

internal sealed class AgentShimDirectoryResolver : IAgentShimDirectoryResolver
{
    public string[] ResolveDirectories()
    {
        var installRoot = InstallMetadata.ResolveInstallDirectory();
        var values = new List<string>
        {
            "/opt/containai/agent-shims",
            "/opt/containai/user-agent-shims",
        };

        if (!string.IsNullOrWhiteSpace(installRoot))
        {
            values.Add(Path.Combine(installRoot, "agent-shims"));
            values.Add(Path.Combine(installRoot, "user-agent-shims"));
        }

        return values
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }
}
