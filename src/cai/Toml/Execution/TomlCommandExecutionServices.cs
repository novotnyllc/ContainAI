namespace ContainAI.Cli.Host;

internal sealed class TomlCommandExecutionServices
{
    private readonly ITomlCommandFileIo fileIo;
    private readonly ITomlCommandParser parser;
    private readonly ITomlCommandLoadService loadService;
    private readonly ITomlCommandSerializer serializer;
    private readonly ITomlCommandUpdater updater;
    private readonly ITomlCommandValidator validator;

    public TomlCommandExecutionServices(
        ITomlCommandFileIo fileIo,
        ITomlCommandParser parser,
        ITomlCommandSerializer serializer,
        ITomlCommandUpdater updater,
        ITomlCommandValidator validator)
        : this(
            fileIo,
            parser,
            new TomlCommandLoadService(fileIo, parser),
            serializer,
            updater,
            validator)
    {
    }

    internal TomlCommandExecutionServices(
        ITomlCommandFileIo fileIo,
        ITomlCommandParser parser,
        ITomlCommandLoadService loadService,
        ITomlCommandSerializer serializer,
        ITomlCommandUpdater updater,
        ITomlCommandValidator validator)
    {
        this.fileIo = fileIo ?? throw new ArgumentNullException(nameof(fileIo));
        this.parser = parser ?? throw new ArgumentNullException(nameof(parser));
        this.loadService = loadService ?? throw new ArgumentNullException(nameof(loadService));
        this.serializer = serializer ?? throw new ArgumentNullException(nameof(serializer));
        this.updater = updater ?? throw new ArgumentNullException(nameof(updater));
        this.validator = validator ?? throw new ArgumentNullException(nameof(validator));
    }

    public bool FileExists(string filePath) => fileIo.FileExists(filePath);

    public TomlCommandResult WriteConfig(string filePath, string content)
        => fileIo.WriteConfig(filePath, content);

    public bool TryReadText(string filePath, out string content, out string? error)
        => fileIo.TryReadText(filePath, out content, out error);

    public TomlLoadResult LoadToml(string filePath, int missingFileExitCode, string? missingFileMessage)
        => loadService.LoadToml(filePath, missingFileExitCode, missingFileMessage);

    public bool TryGetNestedValue(IReadOnlyDictionary<string, object?> table, string key, out object? value)
        => parser.TryGetNestedValue(table, key, out value);

    public object GetWorkspaceState(IReadOnlyDictionary<string, object?> table, string workspacePath)
        => parser.GetWorkspaceState(table, workspacePath);

    public TomlCommandResult SerializeAsJson(IReadOnlyDictionary<string, object?> table)
        => serializer.SerializeAsJson(table);

    public string SerializeJsonValue(object? value)
        => serializer.SerializeJsonValue(value);

    public string FormatValue(object? value)
        => serializer.FormatValue(value);

    public string UpsertWorkspaceKey(string content, string workspacePath, string key, string value)
        => updater.UpsertWorkspaceKey(content, workspacePath, key, value);

    public string RemoveWorkspaceKey(string content, string workspacePath, string key)
        => updater.RemoveWorkspaceKey(content, workspacePath, key);

    public string UpsertGlobalKey(string content, string[] keyParts, string formattedValue)
        => updater.UpsertGlobalKey(content, keyParts, formattedValue);

    public string RemoveGlobalKey(string content, string[] keyParts)
        => updater.RemoveGlobalKey(content, keyParts);

    public string? FormatTomlValueForKey(string key, string value)
        => validator.FormatTomlValueForKey(key, value);

    public TomlEnvValidationResult ValidateEnvSection(IReadOnlyDictionary<string, object?> table)
        => validator.ValidateEnvSection(table);

    public TomlAgentValidationResult ValidateAgentSection(IReadOnlyDictionary<string, object?> table, string sourceFile)
        => validator.ValidateAgentSection(table, sourceFile);
}
