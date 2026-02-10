namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathResolver
{
    internal static bool TryResolveAdditionalImportPath(
        string? rawPath,
        string sourceRoot,
        bool excludePriv,
        out ImportAdditionalPath resolved,
        out string? warning)
    {
        resolved = default;

        if (!ImportAdditionalPathValidation.TryValidateAdditionalPathEntry(rawPath, out warning))
        {
            return false;
        }

        var validatedRawPath = rawPath!;
        if (!ImportAdditionalPathNormalization.TryResolveNormalizedAdditionalPath(validatedRawPath, sourceRoot, out var effectiveHome, out var fullPath, out warning))
        {
            return false;
        }

        if (!ImportAdditionalPathBoundaryChecks.TryValidateAdditionalPathBoundaries(validatedRawPath, effectiveHome, fullPath, out warning))
        {
            return false;
        }

        if (!ImportAdditionalPathTargetMapping.TryMapAdditionalPathTarget(validatedRawPath, effectiveHome, fullPath, out var targetRelativePath, out warning))
        {
            return false;
        }

        var isDirectory = Directory.Exists(fullPath);
        var applyPrivFilter = excludePriv && IsBashrcDirectoryPath(effectiveHome, fullPath);
        resolved = new ImportAdditionalPath(fullPath, targetRelativePath, isDirectory, applyPrivFilter);
        warning = null;
        return true;
    }

    private static bool IsBashrcDirectoryPath(string homeDirectory, string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        var bashrcDirectory = Path.Combine(Path.GetFullPath(homeDirectory), ".bashrc.d");
        return ImportAdditionalPathBoundaryChecks.IsPathWithinDirectory(normalized, bashrcDirectory);
    }
}
