namespace ContainAI.Cli.Host;

internal sealed partial class InstallPathResolver
{
    public string? ResolveCurrentExecutablePath()
    {
        var processPath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(processPath))
        {
            return null;
        }

        return File.Exists(processPath) ? processPath : null;
    }
}
