namespace ContainAI.Cli.Host.Importing.Paths;

internal static partial class ImportAdditionalPathBoundaryChecks
{
    internal static bool TryValidateAdditionalPathBoundaries(
        string rawPath,
        string effectiveHome,
        string fullPath,
        out string? warning)
    {
        if (!TryValidatePathWithinHome(rawPath, fullPath, effectiveHome, out warning))
        {
            return false;
        }

        if (!PathExists(fullPath))
        {
            warning = null;
            return false;
        }

        if (!TryValidateNoSymlinkComponents(rawPath, effectiveHome, fullPath, out warning))
        {
            return false;
        }

        return true;
    }
}
