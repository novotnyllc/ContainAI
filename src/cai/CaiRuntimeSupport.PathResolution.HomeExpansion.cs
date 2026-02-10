namespace ContainAI.Cli.Host;

internal static class CaiRuntimeHomePathHelpers
{
    internal static string ResolveHomeDirectory()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("HOME");
        }

        return string.IsNullOrWhiteSpace(home) ? Directory.GetCurrentDirectory() : home;
    }

    internal static string ExpandHomePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return path;
        }

        if (!path.StartsWith('~'))
        {
            return path;
        }

        var home = ResolveHomeDirectory();
        if (path.Length == 1)
        {
            return home;
        }

        return path[1] switch
        {
            '/' or '\\' => Path.Combine(home, path[2..]),
            _ => path,
        };
    }
}
