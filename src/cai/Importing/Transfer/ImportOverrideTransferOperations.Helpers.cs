namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportOverrideTransferOperations
{
    private static bool ShouldSkipOverrideForNoSecrets(string mappedFlags, bool noSecrets)
        => noSecrets && mappedFlags.Contains('s', StringComparison.Ordinal);

    private static string BuildOverrideCopyCommand(string relativePath, string mappedTargetPath)
        => $"src='/override/{EscapeForSingleQuotedShell(relativePath.TrimStart('/'))}'; " +
           $"dest='/target/{EscapeForSingleQuotedShell(mappedTargetPath)}'; " +
           "mkdir -p \"$(dirname \"$dest\")\"; cp -f \"$src\" \"$dest\"; chown 1000:1000 \"$dest\" || true";
}
