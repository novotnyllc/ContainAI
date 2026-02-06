using System.Reflection;

namespace ContainAI.Cli.Host;

public static class InstallMetadata
{
    private static readonly string[] RootMarkers =
    [
        "ContainAI.slnx",
        "version.json",
        "install.sh",
    ];

    public static (string Version, string InstallType, string InstallDir) ResolveVersionInfo()
    {
        var installDir = ResolveInstallDirectory();
        var version = ResolveVersion();
        var installType = ResolveInstallType(installDir);
        return (version, installType, installDir);
    }

    public static string ResolveInstallDirectory()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in new[] { AppContext.BaseDirectory, Directory.GetCurrentDirectory() })
        {
            var current = Path.GetFullPath(root);
            while (!string.IsNullOrWhiteSpace(current))
            {
                if (seen.Add(current) && IsInstallRoot(current))
                {
                    return current;
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }

        return Directory.GetCurrentDirectory();
    }

    public static string ResolveVersion()
    {
        var entryAssembly = Assembly.GetEntryAssembly();
        var informationalVersion = entryAssembly?.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;

        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return informationalVersion!;
        }

        var assemblyVersion = entryAssembly?.GetName().Version?.ToString()
            ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString();

        return string.IsNullOrWhiteSpace(assemblyVersion) ? "0.0.0" : assemblyVersion;
    }

    public static string ResolveInstallType(string installDir)
    {
        if (Directory.Exists(Path.Combine(installDir, ".git")))
        {
            return "git";
        }

        var normalized = installDir.Replace('\\', '/');
        if (normalized.Contains("/.local/share/containai", StringComparison.Ordinal))
        {
            return "local";
        }

        return "installed";
    }

    private static bool IsInstallRoot(string path)
    {
        if (RootMarkers.Any(marker => File.Exists(Path.Combine(path, marker))))
        {
            return true;
        }

        return Directory.Exists(Path.Combine(path, "manifests")) &&
               Directory.Exists(Path.Combine(path, "templates")) &&
               Directory.Exists(Path.Combine(path, "container"));
    }
}
