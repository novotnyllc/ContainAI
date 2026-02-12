namespace ContainAI.Cli.Host.Sessions.Infrastructure;

internal static class SessionRuntimePathHelpers
{
    internal static string NormalizeWorkspacePath(string path) => Path.GetFullPath(ExpandHome(path));

    internal static string ExpandHome(string value)
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

    internal static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    internal static string ResolveConfigDirectory()
    {
        var xdgConfig = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var root = string.IsNullOrWhiteSpace(xdgConfig)
            ? Path.Combine(ResolveHomeDirectory(), ".config")
            : xdgConfig;
        return Path.Combine(root, "containai");
    }

    internal static string ResolveUserConfigPath() => Path.Combine(ResolveConfigDirectory(), "config.toml");

    internal static string ResolveSshPrivateKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai");

    internal static string ResolveSshPublicKeyPath() => Path.Combine(ResolveConfigDirectory(), "id_containai.pub");

    internal static string ResolveKnownHostsFilePath() => Path.Combine(ResolveConfigDirectory(), "known_hosts");

    internal static string ResolveSshConfigDir() => Path.Combine(ResolveHomeDirectory(), ".ssh", "containai.d");

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
