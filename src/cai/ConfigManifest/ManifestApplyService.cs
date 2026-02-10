using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestApplyService
{
    private readonly IManifestApplier manifestApplier;

    public ManifestApplyService(IManifestApplier manifestApplier)
        => this.manifestApplier = manifestApplier ?? throw new ArgumentNullException(nameof(manifestApplier));

    internal int ApplyManifest(
        string kind,
        string manifestPath,
        string dataDir,
        string homeDir,
        string shimDir,
        string caiBinaryPath) =>
        kind switch
        {
            "container-links" => manifestApplier.ApplyContainerLinks(manifestPath, homeDir, dataDir),
            "init-dirs" => manifestApplier.ApplyInitDirs(manifestPath, dataDir),
            "agent-shims" => manifestApplier.ApplyAgentShims(manifestPath, shimDir, caiBinaryPath),
            _ => throw new InvalidOperationException($"unknown apply kind: {kind}"),
        };

    internal int ApplyInitDirsProbe(string manifestDirectory)
    {
        var initProbeDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-check-{Guid.NewGuid():N}");
        try
        {
            return manifestApplier.ApplyInitDirs(manifestDirectory, initProbeDir);
        }
        finally
        {
            if (Directory.Exists(initProbeDir))
            {
                Directory.Delete(initProbeDir, recursive: true);
            }
        }
    }
}
