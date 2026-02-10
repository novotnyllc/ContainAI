namespace ContainAI.Cli.Host;

internal static class ManifestTomlFileResolver
{
    public static string[] Resolve(string manifestPath)
    {
        if (Directory.Exists(manifestPath))
        {
            var files = Directory
                .EnumerateFiles(manifestPath, "*.toml", SearchOption.TopDirectoryOnly)
                .OrderBy(static file => file, StringComparer.Ordinal)
                .ToArray();

            if (files.Length == 0)
            {
                throw new InvalidOperationException($"no .toml files found in directory: {manifestPath}");
            }

            return files;
        }

        if (File.Exists(manifestPath))
        {
            return [manifestPath];
        }

        throw new InvalidOperationException($"manifest file or directory not found: {manifestPath}");
    }
}
