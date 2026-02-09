namespace ContainAI.Cli.Host;

internal static partial class ManifestApplier
{
    public static int ApplyInitDirs(string manifestPath, string dataDirectory)
        => ApplyInitDirs(manifestPath, dataDirectory, new ManifestTomlParser());

    public static int ApplyInitDirs(string manifestPath, string dataDirectory, IManifestTomlParser manifestTomlParser)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);

        var dataRoot = Path.GetFullPath(dataDirectory);
        Directory.CreateDirectory(dataRoot);

        var parsed = manifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);
        var applied = 0;

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || entry.Flags.Contains('G', StringComparison.Ordinal))
            {
                continue;
            }

            if (entry.Flags.Contains('f', StringComparison.Ordinal) && string.IsNullOrWhiteSpace(entry.ContainerLink))
            {
                continue;
            }

            var fullPath = CombineUnderRoot(dataRoot, entry.Target, "target");
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                EnsureDirectory(fullPath);
                if (entry.Flags.Contains('s', StringComparison.Ordinal))
                {
                    SetUnixModeIfSupported(fullPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
                }

                applied++;
                continue;
            }

            if (!entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            if (entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                SetUnixModeIfSupported(fullPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            }

            applied++;
        }

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "symlink", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || !entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            var fullPath = CombineUnderRoot(dataRoot, entry.Target, "target");
            EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            applied++;
        }

        return applied;
    }
}
