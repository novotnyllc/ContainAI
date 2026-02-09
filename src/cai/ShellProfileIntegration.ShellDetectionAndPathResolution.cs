namespace ContainAI.Cli.Host;

internal sealed partial class ShellProfileIntegrationService
{
    public string GetProfileDirectoryPath(string homeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        return Path.Combine(homeDirectory, ".config", "containai", "profile.d");
    }

    public string GetProfileScriptPath(string homeDirectory)
        => Path.Combine(GetProfileDirectoryPath(homeDirectory), ProfileScriptFileName);

    public string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);

        var shellName = Path.GetFileName(shellPath ?? string.Empty);
        return shellName switch
        {
            "zsh" => Path.Combine(homeDirectory, ".zshrc"),
            _ => File.Exists(Path.Combine(homeDirectory, ".bash_profile"))
                ? Path.Combine(homeDirectory, ".bash_profile")
                : Path.Combine(homeDirectory, ".bashrc"),
        };
    }

    public IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);

        var candidates = new List<string>
        {
            ResolvePreferredShellProfilePath(homeDirectory, shellPath),
            Path.Combine(homeDirectory, ".bash_profile"),
            Path.Combine(homeDirectory, ".bashrc"),
            Path.Combine(homeDirectory, ".zshrc"),
        };

        return candidates
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    private static string NormalizePathForShell(string homeDirectory, string path)
    {
        var normalizedHome = Path.GetFullPath(homeDirectory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Replace('\\', '/');
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Replace('\\', '/');

        if (string.Equals(normalizedPath, normalizedHome, StringComparison.Ordinal))
        {
            return "$HOME";
        }

        if (normalizedPath.StartsWith(normalizedHome + "/", StringComparison.Ordinal))
        {
            return "$HOME/" + normalizedPath[(normalizedHome.Length + 1)..];
        }

        return normalizedPath;
    }
}
