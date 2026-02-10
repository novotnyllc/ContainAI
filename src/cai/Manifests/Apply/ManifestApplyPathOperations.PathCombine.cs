namespace ContainAI.Cli.Host.Manifests.Apply;

internal static partial class ManifestApplyPathOperations
{
    public static string CombineUnderRoot(string root, string relativePath, string fieldName)
    {
        if (Path.IsPathRooted(relativePath))
        {
            throw new InvalidOperationException($"{fieldName} must be relative: {relativePath}");
        }

        var combined = Path.GetFullPath(Path.Combine(root, relativePath));
        if (string.Equals(combined, root, StringComparison.Ordinal))
        {
            return combined;
        }

        if (!combined.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{fieldName} escapes root: {relativePath}");
        }

        return combined;
    }
}
