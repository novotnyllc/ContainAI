namespace ContainAI.Cli.Host.RuntimeSupport.Paths;

internal static class CaiRuntimeConfigLocator
{
    internal static string ResolveUserConfigPath(IReadOnlyList<string> configFileNames)
    {
        var containAiConfigDirectory = CaiRuntimeConfigRoot.ResolveContainAiConfigDirectory();
        return Path.Combine(containAiConfigDirectory, configFileNames[0]);
    }

    internal static string? TryFindExistingUserConfigPath(IReadOnlyList<string> configFileNames)
    {
        var containAiConfigDirectory = CaiRuntimeConfigRoot.ResolveContainAiConfigDirectory();
        foreach (var fileName in configFileNames)
        {
            var candidate = Path.Combine(containAiConfigDirectory, fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    internal static string ResolveConfigPath(string? workspacePath, IReadOnlyList<string> configFileNames)
    {
        var explicitConfigPath = System.Environment.GetEnvironmentVariable("CONTAINAI_CONFIG");
        if (!string.IsNullOrWhiteSpace(explicitConfigPath))
        {
            return Path.GetFullPath(CaiRuntimeHomePathHelpers.ExpandHomePath(explicitConfigPath));
        }

        var workspaceConfigPath = CaiRuntimeWorkspacePathHelpers.TryFindWorkspaceConfigPath(workspacePath, configFileNames);
        if (!string.IsNullOrWhiteSpace(workspaceConfigPath))
        {
            return workspaceConfigPath;
        }

        var userConfigPath = TryFindExistingUserConfigPath(configFileNames);
        return userConfigPath ?? ResolveUserConfigPath(configFileNames);
    }
}
