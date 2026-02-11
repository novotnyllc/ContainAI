namespace ContainAI.Cli.Host.Importing.Transfer;

internal static class ImportManifestTargetSkipPolicy
{
    public static bool ShouldSkipForNoSecrets(ManifestEntry entry, bool noSecrets)
        => noSecrets && IsSecretEntry(entry);

    public static bool IsSecretEntry(ManifestEntry entry)
        => entry.Flags.Contains('s', StringComparison.Ordinal);
}
