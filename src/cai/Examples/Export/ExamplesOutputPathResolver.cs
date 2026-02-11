namespace ContainAI.Cli.Host;

internal interface IExamplesOutputPathResolver
{
    string NormalizePath(string value);
}

internal sealed class ExamplesOutputPathResolver : IExamplesOutputPathResolver
{
    public string NormalizePath(string value)
    {
        if (string.Equals(value, "~", StringComparison.Ordinal))
        {
            return ResolveHomeDirectory();
        }

        if (value.StartsWith("~/", StringComparison.Ordinal))
        {
            return Path.GetFullPath(Path.Combine(ResolveHomeDirectory(), value[2..]));
        }

        return Path.GetFullPath(value);
    }

    private static string ResolveHomeDirectory()
    {
        var home = Environment.GetEnvironmentVariable("HOME");
        if (!string.IsNullOrWhiteSpace(home))
        {
            return home;
        }

        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(userProfile))
        {
            return userProfile;
        }

        return Directory.GetCurrentDirectory();
    }
}
