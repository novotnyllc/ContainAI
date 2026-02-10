namespace ContainAI.Cli.Host;

internal static class TomlGlobalKeyUpdater
{
    public static string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => TomlGlobalKeyUpsertor.UpsertGlobalKey(content, keyParts, formattedValue);

    public static string RemoveGlobalKey(string content, string[] keyParts)
        => TomlGlobalKeyRemover.RemoveGlobalKey(content, keyParts);
}
