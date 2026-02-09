namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandRuntime
{
    private static string? ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return null;
        }

        return File.Exists(processPath) ? processPath : null;
    }

    private static string ResolveInstallDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            Environment.GetEnvironmentVariable("CAI_INSTALL_DIR"),
            ContainAiDataHomeRelative);

    private static string ResolveBinDirectory(string? optionValue)
        => ResolveDirectory(
            optionValue,
            Environment.GetEnvironmentVariable("CAI_BIN_DIR"),
            ContainAiBinHomeRelative);

    private static string ResolveDirectory(string? optionValue, string? envValue, string homeRelative)
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

    private static string NormalizePath(string value)
    {
        var expanded = value.StartsWith("~/", StringComparison.Ordinal) || string.Equals(value, "~", StringComparison.Ordinal)
            ? Path.Combine(ResolveHomeDirectory(), value.Length == 1 ? string.Empty : value[2..])
            : value;

        return Path.GetFullPath(expanded);
    }
}
