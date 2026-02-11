namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimeConfigRoot
{
    internal static string ResolveContainAiConfigDirectory()
    {
        var home = CaiRuntimeHomePathHelpers.ResolveHomeDirectory();
        var xdgConfigHome = System.Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai");
    }

    internal static string ResolveTemplatesDirectory()
    {
        var containAiConfigDirectory = ResolveContainAiConfigDirectory();
        return Path.Combine(containAiConfigDirectory, "templates");
    }
}
