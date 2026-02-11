using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ConfigManifest;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService : CaiRuntimeSupport
{
    private readonly IConfigCommandProcessor configCommandProcessor;
    private readonly IManifestCommandProcessor manifestCommandProcessor;

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
