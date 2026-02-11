namespace ContainAI.Cli.Host;

internal sealed partial class TomlCommandExecutionServices
{
    private readonly ITomlCommandFileIo fileIo;
    private readonly ITomlCommandParser parser;
    private readonly ITomlCommandSerializer serializer;
    private readonly ITomlCommandUpdater updater;
    private readonly ITomlCommandValidator validator;

    public TomlCommandExecutionServices(
        ITomlCommandFileIo fileIo,
        ITomlCommandParser parser,
        ITomlCommandSerializer serializer,
        ITomlCommandUpdater updater,
        ITomlCommandValidator validator)
    {
        this.fileIo = fileIo;
        this.parser = parser;
        this.serializer = serializer;
        this.updater = updater;
        this.validator = validator;
    }
}
