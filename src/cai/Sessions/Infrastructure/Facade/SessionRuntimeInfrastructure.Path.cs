namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static string NormalizeWorkspacePath(string path) => SessionRuntimePathHelpers.NormalizeWorkspacePath(path);

    public static string ExpandHome(string value) => SessionRuntimePathHelpers.ExpandHome(value);

    public static string ResolveHomeDirectory() => SessionRuntimePathHelpers.ResolveHomeDirectory();

    public static string ResolveConfigDirectory() => SessionRuntimePathHelpers.ResolveConfigDirectory();

    public static string ResolveUserConfigPath() => SessionRuntimePathHelpers.ResolveUserConfigPath();

    public static string ResolveSshPrivateKeyPath() => SessionRuntimePathHelpers.ResolveSshPrivateKeyPath();

    public static string ResolveSshPublicKeyPath() => SessionRuntimePathHelpers.ResolveSshPublicKeyPath();

    public static string ResolveKnownHostsFilePath() => SessionRuntimePathHelpers.ResolveKnownHostsFilePath();

    public static string ResolveSshConfigDir() => SessionRuntimePathHelpers.ResolveSshConfigDir();

    public static string FindConfigFile(string workspace, string? explicitConfig)
        => SessionRuntimePathHelpers.FindConfigFile(workspace, explicitConfig);
}
