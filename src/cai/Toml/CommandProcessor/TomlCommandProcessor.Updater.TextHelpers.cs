namespace ContainAI.Cli.Host;

internal static partial class TomlCommandUpdaterLineHelpers
{
    public static bool IsAnyTableHeader(string trimmed) => trimmed.StartsWith('[');

    public static bool IsTargetHeader(string trimmed, string header)
    {
        if (string.Equals(trimmed, header, StringComparison.Ordinal))
        {
            return true;
        }

        if (trimmed.StartsWith(header, StringComparison.Ordinal) && trimmed.Length > header.Length)
        {
            var remainder = trimmed[header.Length..].TrimStart();
            return remainder.StartsWith('#');
        }

        return false;
    }
}
