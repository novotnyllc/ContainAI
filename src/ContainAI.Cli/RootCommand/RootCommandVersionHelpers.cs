using System.Text.Encodings.Web;
using ContainAI.Cli.Host;

namespace ContainAI.Cli;

internal static class RootCommandVersionHelpers
{
    internal static string GetVersionJson()
    {
        var versionInfo = InstallMetadata.ResolveVersionInfo();
        var installType = InstallMetadata.GetInstallTypeLabel(versionInfo.InstallType);

        return $"{{\"version\":\"{JavaScriptEncoder.Default.Encode(versionInfo.Version)}\",\"install_type\":\"{JavaScriptEncoder.Default.Encode(installType)}\",\"install_dir\":\"{JavaScriptEncoder.Default.Encode(versionInfo.InstallDir)}\"}}";
    }
}
