namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimePathHelpers
{
    internal static string FindConfigFile(string workspace, string? explicitConfig)
    {
        if (!string.IsNullOrWhiteSpace(explicitConfig))
        {
            return Path.GetFullPath(ExpandHome(explicitConfig));
        }

        var current = Path.GetFullPath(workspace);
        while (!string.IsNullOrWhiteSpace(current))
        {
            var candidate = Path.Combine(current, ".containai", "config.toml");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            if (File.Exists(Path.Combine(current, ".git")) || Directory.Exists(Path.Combine(current, ".git")))
            {
                break;
            }

            var parent = Directory.GetParent(current);
            if (parent is null)
            {
                break;
            }

            current = parent.FullName;
        }

        var userConfig = ResolveUserConfigPath();
        return File.Exists(userConfig) ? userConfig : string.Empty;
    }
}
