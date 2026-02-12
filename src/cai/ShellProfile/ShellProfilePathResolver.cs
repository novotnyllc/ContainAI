namespace ContainAI.Cli.Host;

internal sealed class ShellProfilePathResolver : IShellProfilePathResolver
{
    public string GetProfileDirectoryPath(string homeDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(homeDirectory);
        return Path.Combine(homeDirectory, ".config", "containai", "profile.d");
    }

    public string GetProfileScriptPath(string homeDirectory)
        => Path.Combine(GetProfileDirectoryPath(homeDirectory), ShellProfileIntegrationConstants.ProfileScriptFileName);

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
}
