namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string NormalizeWorkspacePath(string path) => Path.GetFullPath(ExpandHome(path));

    public static string ExpandHome(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || !value.StartsWith('~'))
        {
            return value;
        }

        var home = ResolveHomeDirectory();
        if (value.Length == 1)
        {
            return home;
        }

        return value[1] switch
        {
            '/' or '\\' => Path.Combine(home, value[2..]),
            _ => value,
        };
    }

    public static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    public static string ResolveConfigDirectory()
    {
        var xdgConfig = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var root = string.IsNullOrWhiteSpace(xdgConfig)
            ? Path.Combine(ResolveHomeDirectory(), ".config")
            : xdgConfig;
        return Path.Combine(root, "containai");
    }

    public static string ResolveUserConfigPath() => Path.Combine(ResolveConfigDirectory(), "config.toml");

    public static string ResolveSshPrivateKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai");

    public static string ResolveSshPublicKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai.pub");

    public static string ResolveKnownHostsFilePath() => Path.Combine(ResolveConfigDirectory(), "known_hosts");

    public static string ResolveSshConfigDir() => Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");

    public static string FindConfigFile(string workspace, string? explicitConfig)
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
