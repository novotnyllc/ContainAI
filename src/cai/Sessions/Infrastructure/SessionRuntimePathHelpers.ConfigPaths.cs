namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimePathHelpers
{
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
}
