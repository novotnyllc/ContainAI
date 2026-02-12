namespace ContainAI.Cli.Host;

internal interface IInstallPathResolver
{
    string? ResolveCurrentExecutablePath();

    string ResolveInstallDirectory(string? optionValue);

    string ResolveBinDirectory(string? optionValue);

    string ResolveHomeDirectory();

    string? GetEnvironmentVariable(string variableName);
}
