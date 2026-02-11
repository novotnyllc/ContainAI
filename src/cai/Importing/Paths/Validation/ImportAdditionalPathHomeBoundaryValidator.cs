namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathHomeBoundaryValidator
{
    public static bool TryValidate(string rawPath, string fullPath, string effectiveHome, out string? warning)
    {
        if (ImportAdditionalPathBoundaryChecks.IsPathWithinDirectory(fullPath, effectiveHome))
        {
            warning = null;
            return true;
        }

        warning = $"[WARN] [import].additional_paths '{rawPath}' escapes HOME; skipping";
        return false;
    }
}
