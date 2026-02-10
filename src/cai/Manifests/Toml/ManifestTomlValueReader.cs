namespace ContainAI.Cli.Host;

internal static class ManifestTomlValueReader
{
    public static string ReadString(string? value) => value ?? string.Empty;

    public static List<string> ReadStringArray(string[]? values)
        => values?
            .Where(static value => !string.IsNullOrWhiteSpace(value))
            .ToList()
        ?? [];
}
