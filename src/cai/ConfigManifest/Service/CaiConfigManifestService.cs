using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host;

internal sealed class CaiConfigManifestService
{
    private readonly CaiConfigCommandHandler configCommandHandler;
    private readonly CaiManifestCommandHandler manifestCommandHandler;

    public CaiConfigManifestService(TextWriter standardOutput, TextWriter standardError)
        : this(standardOutput, standardError, new ManifestTomlParser())
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser)
        : this(standardOutput, standardError, manifestTomlParser, new ManifestApplier(manifestTomlParser))
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier)
        : this(
            standardOutput,
            standardError,
            manifestTomlParser,
            manifestApplier,
            CaiConfigManifestProcessorFactory.CreateConfigCommandProcessor(standardOutput, standardError),
            CaiConfigManifestProcessorFactory.CreateManifestCommandProcessor(standardOutput, standardError, manifestTomlParser, manifestApplier))
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier,
        IConfigCommandProcessor configCommandProcessor,
        IManifestCommandProcessor manifestCommandProcessor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(manifestApplier);

        configCommandHandler = new CaiConfigCommandHandler(configCommandProcessor ?? throw new ArgumentNullException(nameof(configCommandProcessor)));
        manifestCommandHandler = new CaiManifestCommandHandler(manifestCommandProcessor ?? throw new ArgumentNullException(nameof(manifestCommandProcessor)));
    }

    public Task<int> RunConfigListAsync(ConfigListCommandOptions options, CancellationToken cancellationToken)
        => configCommandHandler.RunConfigListAsync(options, cancellationToken);

    public Task<int> RunConfigGetAsync(ConfigGetCommandOptions options, CancellationToken cancellationToken)
        => configCommandHandler.RunConfigGetAsync(options, cancellationToken);

    public Task<int> RunConfigSetAsync(ConfigSetCommandOptions options, CancellationToken cancellationToken)
        => configCommandHandler.RunConfigSetAsync(options, cancellationToken);

    public Task<int> RunConfigUnsetAsync(ConfigUnsetCommandOptions options, CancellationToken cancellationToken)
        => configCommandHandler.RunConfigUnsetAsync(options, cancellationToken);

    public Task<int> RunConfigResolveVolumeAsync(ConfigResolveVolumeCommandOptions options, CancellationToken cancellationToken)
        => configCommandHandler.RunConfigResolveVolumeAsync(options, cancellationToken);

    public Task<int> RunManifestParseAsync(ManifestParseCommandOptions options, CancellationToken cancellationToken)
        => manifestCommandHandler.RunManifestParseAsync(options, cancellationToken);

    public Task<int> RunManifestGenerateAsync(ManifestGenerateCommandOptions options, CancellationToken cancellationToken)
        => manifestCommandHandler.RunManifestGenerateAsync(options, cancellationToken);

    public Task<int> RunManifestApplyAsync(ManifestApplyCommandOptions options, CancellationToken cancellationToken)
        => manifestCommandHandler.RunManifestApplyAsync(options, cancellationToken);

    public Task<int> RunManifestCheckAsync(ManifestCheckCommandOptions options, CancellationToken cancellationToken)
        => manifestCommandHandler.RunManifestCheckAsync(options, cancellationToken);
}
