using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli;

public sealed class DefaultContainAiScriptResolver : IContainAiScriptResolver
{
    private const string OverrideVariable = "CAI_BASH_SCRIPT";

    public string ResolveScriptPath()
    {
        var overridePath = Environment.GetEnvironmentVariable(OverrideVariable);
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            var fullOverridePath = Path.GetFullPath(Environment.ExpandEnvironmentVariables(overridePath));
            if (IsValidContainAiScript(fullOverridePath))
            {
                return fullOverridePath;
            }

            throw new FileNotFoundException(
                $"{OverrideVariable} points to '{fullOverridePath}', but containai.sh was not found or is invalid.");
        }

        foreach (var candidate in EnumerateCandidates())
        {
            if (IsValidContainAiScript(candidate))
            {
                return Path.GetFullPath(candidate);
            }
        }

        throw new FileNotFoundException(
            "Unable to locate containai.sh. Set CAI_BASH_SCRIPT to the script path or install containai runtime assets.");
    }

    private static IEnumerable<string> EnumerateCandidates()
    {
        var baseDirectory = AppContext.BaseDirectory;
        var currentDirectory = Directory.GetCurrentDirectory();

        yield return Path.Combine(baseDirectory, "containai.sh");
        yield return Path.Combine(baseDirectory, "src", "containai.sh");
        yield return Path.Combine(currentDirectory, "containai.sh");
        yield return Path.Combine(currentDirectory, "src", "containai.sh");

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(home))
        {
            yield return Path.Combine(home, ".local", "share", "containai", "containai.sh");
        }

        yield return "/usr/local/share/containai/containai.sh";

        foreach (var rootedPath in EnumerateParentCandidates(baseDirectory))
        {
            yield return rootedPath;
        }

        foreach (var rootedPath in EnumerateParentCandidates(currentDirectory))
        {
            yield return rootedPath;
        }
    }

    private static IEnumerable<string> EnumerateParentCandidates(string startPath)
    {
        var directory = new DirectoryInfo(Path.GetFullPath(startPath));

        while (directory is not null)
        {
            yield return Path.Combine(directory.FullName, "containai.sh");
            yield return Path.Combine(directory.FullName, "src", "containai.sh");
            directory = directory.Parent;
        }
    }

    private static bool IsValidContainAiScript(string path)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        var scriptDirectory = Path.GetDirectoryName(path);
        if (string.IsNullOrWhiteSpace(scriptDirectory))
        {
            return false;
        }

        if (File.Exists(Path.Combine(scriptDirectory, "lib", "core.sh")))
        {
            return true;
        }

        if (path.EndsWith(Path.Combine("src", "containai.sh"), StringComparison.Ordinal) &&
            File.Exists(Path.Combine(scriptDirectory, "lib", "core.sh")))
        {
            return true;
        }

        return false;
    }
}
