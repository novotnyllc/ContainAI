namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathValidation
{
    internal static bool TryValidateAdditionalPathEntry(string? rawPath, out string? warning)
    {
        warning = null;

        if (string.IsNullOrWhiteSpace(rawPath))
        {
            warning = "[WARN] [import].additional_paths entry is empty; skipping";
            return false;
        }

        if (rawPath.Contains(':', StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains ':'; skipping";
            return false;
        }

        return true;
    }
}
