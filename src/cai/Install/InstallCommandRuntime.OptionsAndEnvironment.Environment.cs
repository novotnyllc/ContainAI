namespace ContainAI.Cli.Host;

internal sealed partial class InstallPathResolver
{
    public string ResolveHomeDirectory()
    {
        var home = GetEnvironmentVariable("HOME");
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

    public string? GetEnvironmentVariable(string variableName)
        => Environment.GetEnvironmentVariable(variableName);
}
