namespace ContainAI.Cli.Host;

internal static partial class TemplateUtilities
{
    public static string ResolveTemplatesDirectory(string homeDirectory)
    {
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(homeDirectory, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai", "templates");
    }

    public static string ResolveTemplateDockerfilePath(string homeDirectory, string? templateName = null)
    {
        var name = string.IsNullOrWhiteSpace(templateName) ? "default" : templateName;
        return Path.Combine(ResolveTemplatesDirectory(homeDirectory), name, "Dockerfile");
    }
}
