using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService : CaiRuntimeSupport
{
    private readonly IConfigCommandProcessor configCommandProcessor;
    private readonly IManifestCommandProcessor manifestCommandProcessor;

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
            new ConfigCommandProcessor(
                standardOutput,
                standardError,
                new CaiConfigRuntimeAdapter(
                    ResolveConfigPath,
                    ExpandHomePath,
                    NormalizeConfigKey,
                    (request, normalizedKey) =>
                    {
                        var parsed = new ParsedConfigCommand(
                            request.Action,
                            request.Key,
                            request.Value,
                            request.Global,
                            request.Workspace,
                            Error: null);
                        return ResolveWorkspaceScope(parsed, normalizedKey);
                    },
                    async (operation, cancellationToken) =>
                    {
                        var result = await RunTomlAsync(operation, cancellationToken).ConfigureAwait(false);
                        return new TomlProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
                    },
                    ResolveDataVolumeAsync)),
            new ManifestCommandProcessor(
                standardOutput,
                standardError,
                manifestTomlParser,
                manifestApplier,
                new ManifestDirectoryResolver(ExpandHomePath)))
    {
    }

    internal CaiConfigManifestService(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier,
        IConfigCommandProcessor configCommandProcessor,
        IManifestCommandProcessor manifestCommandProcessor)
        : base(standardOutput, standardError)
    {
        ArgumentNullException.ThrowIfNull(manifestTomlParser);
        ArgumentNullException.ThrowIfNull(manifestApplier);
        this.configCommandProcessor = configCommandProcessor ?? throw new ArgumentNullException(nameof(configCommandProcessor));
        this.manifestCommandProcessor = manifestCommandProcessor ?? throw new ArgumentNullException(nameof(manifestCommandProcessor));
    }

}
