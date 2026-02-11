namespace ContainAI.Cli.Host;

internal sealed class TomlSetUnsetContentCoordinator(TomlCommandExecutionServices services)
{
    public TomlCommandResult? GetUnsetNoOpWhenFileMissing(string filePath)
    {
        if (!services.FileExists(filePath))
        {
            return new TomlCommandResult(0, string.Empty, string.Empty);
        }

        return null;
    }

    public TomlCommandResult UpdateContent(string filePath, Func<string, string> update)
    {
        var contentRead = services.TryReadText(filePath, out var content, out var readError);
        if (!contentRead)
        {
            return new TomlCommandResult(1, string.Empty, readError!);
        }

        var updatedContent = update(content);
        return services.WriteConfig(filePath, updatedContent);
    }
}
