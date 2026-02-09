namespace ContainAI.Cli.Host;

internal static partial class ShellProfileIntegration
{
    private const string ShellIntegrationStartMarker = "# >>> ContainAI shell integration >>>";
    private const string ShellIntegrationEndMarker = "# <<< ContainAI shell integration <<<";
    private const string ProfileDirectoryRelativePath = ".config/containai/profile.d";
    private const string ProfileScriptFileName = "containai.sh";
}
