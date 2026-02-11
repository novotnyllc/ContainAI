namespace ContainAI.Cli.Host;

internal interface IShellProfileHookBlockManager
{
    bool HasHookBlock(string content);

    string BuildHookBlock();

    bool TryRemoveHookBlock(string content, out string updated);
}

internal sealed partial class ShellProfileHookBlockManager : IShellProfileHookBlockManager
{
    public bool HasHookBlock(string content)
        => content.Contains(ShellProfileIntegrationConstants.ShellIntegrationStartMarker, StringComparison.Ordinal)
           && content.Contains(ShellProfileIntegrationConstants.ShellIntegrationEndMarker, StringComparison.Ordinal);

    public string BuildHookBlock()
    {
        var profileDirectory = "$HOME/" + ShellProfileIntegrationConstants.ProfileDirectoryRelativePath;
        return string.Join(
            Environment.NewLine,
            ShellProfileIntegrationConstants.ShellIntegrationStartMarker,
            $"if [ -d \"{profileDirectory}\" ]; then",
            $"  for _cai_profile in \"{profileDirectory}/\"*.sh; do",
            "    [ -r \"$_cai_profile\" ] && . \"$_cai_profile\"",
            "  done",
            "  unset _cai_profile",
            "fi",
            ShellProfileIntegrationConstants.ShellIntegrationEndMarker);
    }
}
