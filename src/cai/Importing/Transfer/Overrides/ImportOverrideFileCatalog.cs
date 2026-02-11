using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal static class ImportOverrideFileCatalog
{
    public static string ResolveOverridesDirectory()
        => Path.Combine(
            CaiRuntimeHomePathHelpers.ResolveHomeDirectory(),
            ".config",
            "containai",
            "import-overrides");

    public static string[] GetOverrideFiles(string overridesDirectory)
        => Directory.EnumerateFiles(overridesDirectory, "*", SearchOption.AllDirectories)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
}
