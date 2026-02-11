using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed partial class ContainerRuntimeManifestBootstrapService
{
    public async Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet)
    {
        var userManifestDirectory = Path.Combine(dataDir, "containai", "manifests");
        if (!Directory.Exists(userManifestDirectory))
        {
            return;
        }

        var manifestFiles = Directory.EnumerateFiles(userManifestDirectory, "*.toml", SearchOption.TopDirectoryOnly).ToArray();
        if (manifestFiles.Length == 0)
        {
            return;
        }

        await context.LogInfoAsync(quiet, $"Found {manifestFiles.Length} user manifest(s), generating runtime configuration...").ConfigureAwait(false);
        try
        {
            _ = manifestApplier.ApplyInitDirs(userManifestDirectory, dataDir);
            _ = manifestApplier.ApplyContainerLinks(userManifestDirectory, homeDir, dataDir);
            _ = manifestApplier.ApplyAgentShims(userManifestDirectory, "/opt/containai/user-agent-shims", "/usr/local/bin/cai");

            var userSpec = ManifestGenerators.GenerateContainerLinkSpec(userManifestDirectory, context.ManifestTomlParser);
            var userSpecPath = Path.Combine(dataDir, "containai", "user-link-spec.json");
            Directory.CreateDirectory(Path.GetDirectoryName(userSpecPath)!);
            await File.WriteAllTextAsync(userSpecPath, userSpec.Content).ConfigureAwait(false);
        }
        catch (Exception ex) when (ContainerRuntimeExceptionHandling.IsHandled(ex))
        {
            await context.StandardError.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
    }
}
