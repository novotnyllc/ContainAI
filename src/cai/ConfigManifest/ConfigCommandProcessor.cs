namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ConfigCommandProcessor : IConfigCommandProcessor
{
    private readonly ICaiConfigRuntime runtime;
    private readonly IConfigReadOperation readOperation;
    private readonly IConfigWriteOperation writeOperation;
    private readonly IConfigResolveVolumeOperation resolveVolumeOperation;

    public ConfigCommandProcessor(TextWriter standardOutput, TextWriter standardError, ICaiConfigRuntime runtime)
        : this(
            standardOutput,
            standardError,
            runtime,
            new ConfigReadOperation(standardOutput, standardError, runtime),
            new ConfigWriteOperation(standardError, runtime),
            new ConfigResolveVolumeOperation(standardOutput, runtime))
    {
    }

    internal ConfigCommandProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiConfigRuntime runtime,
        IConfigReadOperation configReadOperation,
        IConfigWriteOperation configWriteOperation,
        IConfigResolveVolumeOperation configResolveVolumeOperation)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        this.runtime = runtime ?? throw new ArgumentNullException(nameof(runtime));
        readOperation = configReadOperation ?? throw new ArgumentNullException(nameof(configReadOperation));
        writeOperation = configWriteOperation ?? throw new ArgumentNullException(nameof(configWriteOperation));
        resolveVolumeOperation = configResolveVolumeOperation ?? throw new ArgumentNullException(nameof(configResolveVolumeOperation));
    }

    public async Task<int> RunAsync(ConfigCommandRequest request, CancellationToken cancellationToken)
    {
        if (string.Equals(request.Action, "resolve-volume", StringComparison.Ordinal))
        {
            return await resolveVolumeOperation.ResolveVolumeAsync(request, cancellationToken).ConfigureAwait(false);
        }

        var configPath = runtime.ResolveConfigPath(request.Workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        return request.Action switch
        {
            "list" => await readOperation.ListAsync(configPath, cancellationToken).ConfigureAwait(false),
            "get" => await readOperation.GetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            "set" => await writeOperation.SetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            "unset" => await writeOperation.UnsetAsync(configPath, request, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }
}
