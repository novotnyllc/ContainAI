namespace ContainAI.Cli.Host;

internal interface IInstallPathResolver
{
    string? ResolveCurrentExecutablePath();

    string ResolveInstallDirectory(string? optionValue);

    string ResolveBinDirectory(string? optionValue);

    string ResolveHomeDirectory();

    string? GetEnvironmentVariable(string variableName);
}

internal sealed class InstallPathResolver : IInstallPathResolver
{
    private const string ContainAiDataHomeRelative = ".local/share/containai";
    private const string ContainAiBinHomeRelative = ".local/bin";

    public string ResolveInstallDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            GetEnvironmentVariable("CAI_INSTALL_DIR"),
            ContainAiDataHomeRelative);

    public string ResolveBinDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            GetEnvironmentVariable("CAI_BIN_DIR"),
            ContainAiBinHomeRelative);

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

    public string? ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return null;
        }

        return File.Exists(processPath) ? processPath : null;
    }

    private string ResolveDirectory(string? optionValue, string? envValue, string homeRelative)
    {
        if (!string.IsNullOrWhiteSpace(optionValue))
        {
            return NormalizePath(optionValue);
        }

        if (!string.IsNullOrWhiteSpace(envValue))
        {
            return NormalizePath(envValue);
        }

        return Path.GetFullPath(Path.Combine(ResolveHomeDirectory(), homeRelative));
    }

    private string NormalizePath(string value)
    {
        var expanded = value.StartsWith("~/", StringComparison.Ordinal) || string.Equals(value, "~", StringComparison.Ordinal)
            ? Path.Combine(ResolveHomeDirectory(), value.Length == 1 ? string.Empty : value[2..])
            : value;

        return Path.GetFullPath(expanded);
    }
}
