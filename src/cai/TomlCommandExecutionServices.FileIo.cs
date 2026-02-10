namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    public bool FileExists(string filePath) => fileIo.FileExists(filePath);

    public TomlCommandResult WriteConfig(string filePath, string content)
        => fileIo.WriteConfig(filePath, content);

    public bool TryReadText(string filePath, out string content, out string? error)
        => fileIo.TryReadText(filePath, out content, out error);
}
