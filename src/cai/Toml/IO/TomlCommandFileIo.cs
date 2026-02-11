namespace ContainAI.Cli.Host;

internal sealed class TomlCommandFileIo : ITomlCommandFileIo
{
    public bool FileExists(string filePath) => File.Exists(filePath);

    public string ReadAllText(string filePath) => File.ReadAllText(filePath);

    public bool TryReadText(string filePath, out string content, out string? error)
        => TomlCommandFileReadService.TryReadText(filePath, out content, out error);

    public TomlCommandResult WriteConfig(string filePath, string content)
        => TomlCommandFileWriteService.WriteConfig(filePath, content);
}
