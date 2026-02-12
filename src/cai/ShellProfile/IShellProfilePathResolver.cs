namespace ContainAI.Cli.Host;

internal interface IShellProfilePathResolver
{
    string GetProfileDirectoryPath(string homeDirectory);

    string GetProfileScriptPath(string homeDirectory);

    string ResolvePreferredShellProfilePath(string homeDirectory, string? shellPath);

    IReadOnlyList<string> GetCandidateShellProfilePaths(string homeDirectory, string? shellPath);
}
