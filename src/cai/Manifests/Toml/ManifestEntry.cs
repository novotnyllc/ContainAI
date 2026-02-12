namespace ContainAI.Cli.Host;

internal readonly record struct ManifestEntry(
    string Source,
    string Target,
    string ContainerLink,
    string Flags,
    bool Disabled,
    string Type,
    bool Optional,
    string? SourceFile)
{
    public override string ToString()
    {
        var disabled = Disabled ? "true" : "false";
        var optional = Optional ? "true" : "false";

        return SourceFile is null
            ? $"{Source}|{Target}|{ContainerLink}|{Flags}|{disabled}|{Type}|{optional}"
            : $"{Source}|{Target}|{ContainerLink}|{Flags}|{disabled}|{Type}|{optional}|{SourceFile}";
    }
}
