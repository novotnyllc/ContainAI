namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string ResolveHostTimeZone() => SessionRuntimeSystemHelpers.ResolveHostTimeZone();

    public static void ParsePortsFromSocketTable(string content, HashSet<int> destination)
        => SessionRuntimeSystemHelpers.ParsePortsFromSocketTable(content, destination);
}
