namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimePathHelpers
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
}
