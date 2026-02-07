using System.Reflection;

namespace ContainAI.Cli.Host;

public enum InstallType
{
    Installed,
    Local,
    Git,
}

public readonly record struct InstallVersionInfo(string Version, InstallType InstallType, string InstallDir);

public static class InstallMetadata
{
    private static readonly string[] RootMarkers =
    [
        "ContainAI.slnx",
        "version.json",
        "install.sh",
    ];

    public static InstallVersionInfo ResolveVersionInfo()
    {
        var installDir = ResolveInstallDirectory();
        var version = ResolveVersion();
        var installType = ResolveInstallType(installDir);
        return new InstallVersionInfo(version, installType, installDir);
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

    public static InstallType ResolveInstallType(string installDir)
    {
        if (Directory.Exists(Path.Combine(installDir, ".git")))
        {
            return InstallType.Git;
        }

        var normalized = installDir.Replace('\\', '/');
        if (normalized.Contains("/.local/share/containai", StringComparison.Ordinal))
        {
            return InstallType.Local;
        }

        return InstallType.Installed;
    }

    public static string GetInstallTypeLabel(InstallType installType)
        => installType switch
        {
            InstallType.Git => "git",
            InstallType.Local => "local",
            _ => "installed",
        };

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
