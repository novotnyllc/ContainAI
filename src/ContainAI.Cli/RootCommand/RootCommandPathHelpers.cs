namespace ContainAI.Cli;

internal static class RootCommandPathHelpers
{
    internal static string ExpandHome(string path)
    {
        if (!path.StartsWith('~'))
        {
            return path;
        }

        var home = Environment.GetEnvironmentVariable("HOME");
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        if (path.Length == 1)
        {
            return home!;
        }

        return path[1] is '/' or '\\'
            ? Path.Combine(home!, path[2..])
            : path;
    }
}
