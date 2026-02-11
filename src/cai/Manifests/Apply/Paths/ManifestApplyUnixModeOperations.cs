using System.Runtime.InteropServices;

namespace ContainAI.Cli.Host.Manifests.Apply.Paths;

internal static class ManifestApplyUnixModeOperations
{
    public static void SetUnixModeIfSupported(string path, UnixFileMode mode)
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return;
        }

        File.SetUnixFileMode(path, mode);
    }
}
