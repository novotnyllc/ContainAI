namespace ContainAI.Cli.Host;

internal static class ShellProfileIntegrationConstants
{
    public const string ShellIntegrationStartMarker = "# >>> ContainAI shell integration >>>";
    public const string ShellIntegrationEndMarker = "# <<< ContainAI shell integration <<<";
    public const string ProfileDirectoryRelativePath = ".config/containai/profile.d";
    public const string ProfileScriptFileName = "containai.sh";
}
