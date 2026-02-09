namespace ContainAI.Cli.Host;

internal abstract partial class CaiRuntimeSupport
{
    protected static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    protected static string ResolveUserConfigPath()
    {
        var containAiConfigDirectory = ResolveContainAiConfigDirectory();
        return Path.Combine(containAiConfigDirectory, ConfigFileNames[0]);
    }

    protected static string? TryFindExistingUserConfigPath()
    {
        var containAiConfigDirectory = ResolveContainAiConfigDirectory();
        foreach (var fileName in ConfigFileNames)
        {
            var candidate = Path.Combine(containAiConfigDirectory, fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    protected static string ResolveConfigPath(string? workspacePath)
    {
        var explicitConfigPath = Environment.GetEnvironmentVariable("CONTAINAI_CONFIG");
        if (!string.IsNullOrWhiteSpace(explicitConfigPath))
        {
            return Path.GetFullPath(ExpandHomePath(explicitConfigPath));
        }

        var workspaceConfigPath = TryFindWorkspaceConfigPath(workspacePath);
        if (!string.IsNullOrWhiteSpace(workspaceConfigPath))
        {
            return workspaceConfigPath;
        }

        var userConfigPath = TryFindExistingUserConfigPath();
        return userConfigPath ?? ResolveUserConfigPath();
    }

    protected static string ResolveTemplatesDirectory()
    {
        var containAiConfigDirectory = ResolveContainAiConfigDirectory();
        return Path.Combine(containAiConfigDirectory, "templates");
    }

    private static string ResolveContainAiConfigDirectory()
    {
        var home = ResolveHomeDirectory();
        var xdgConfigHome = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var configRoot = string.IsNullOrWhiteSpace(xdgConfigHome)
            ? Path.Combine(home, ".config")
            : xdgConfigHome;

        return Path.Combine(configRoot, "containai");
    }
}
