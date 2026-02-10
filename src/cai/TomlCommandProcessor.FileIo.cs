namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandFileIo : ITomlCommandFileIo
{
    public bool FileExists(string filePath) => File.Exists(filePath);

    public string ReadAllText(string filePath) => File.ReadAllText(filePath);
}
