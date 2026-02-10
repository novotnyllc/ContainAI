namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimBinaryResolver
{
    public string ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            return Path.GetFullPath(processPath);
        }

        var argv0 = Environment.GetCommandLineArgs().FirstOrDefault();
        if (string.IsNullOrWhiteSpace(argv0))
        {
            return string.Empty;
        }

        return Path.GetFullPath(argv0);
    }
}
