using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService
{
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
}
