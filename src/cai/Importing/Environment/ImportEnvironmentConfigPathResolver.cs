using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Environment;

internal static class ImportEnvironmentConfigPathResolver
{
    private static readonly string[] ConfigFileNames =
    [
        "config.toml",
        "containai.toml",
    ];

    public static string ResolveEnvironmentConfigPath(string workspace, string? explicitConfigPath)
        => !string.IsNullOrWhiteSpace(explicitConfigPath)
            ? explicitConfigPath
            : CaiRuntimeConfigLocator.ResolveConfigPath(workspace, ConfigFileNames);
}
