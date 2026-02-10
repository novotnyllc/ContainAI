namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestTargetInitializer
{
    private static bool ShouldSkipForNoSecrets(ManifestEntry entry, bool noSecrets)
        => noSecrets && IsSecretEntry(entry);

    private static bool IsSecretEntry(ManifestEntry entry)
        => entry.Flags.Contains('s', StringComparison.Ordinal);
}
