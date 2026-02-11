using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal sealed partial class ContainerRuntimeManifestBootstrapService
{
    public async Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet)
    {
        await context.RunAsRootAsync("mkdir", ["-p", dataDir]).ConfigureAwait(false);
        await context.RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);

        if (Directory.Exists(manifestsDir))
        {
            await context.LogInfoAsync(quiet, "Applying init directory policy from manifests").ConfigureAwait(false);
            try
            {
                _ = manifestApplier.ApplyInitDirs(manifestsDir, dataDir);
            }
            catch (Exception ex) when (ContainerRuntimeExceptionHandling.IsHandled(ex))
            {
                await context.StandardError.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
        }
        else
        {
            await context.StandardError.WriteLineAsync("[WARN] Built-in manifests not found, using fallback volume structure").ConfigureAwait(false);
            EnsureFallbackVolumeStructure(dataDir);
        }

        await context.RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);
    }

    private void EnsureFallbackVolumeStructure(string dataDir)
    {
        Directory.CreateDirectory(Path.Combine(dataDir, "claude"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config", "gh"));
        Directory.CreateDirectory(Path.Combine(dataDir, "git"));
        context.EnsureFileWithContent(Path.Combine(dataDir, "git", "gitconfig"), null);
        context.EnsureFileWithContent(Path.Combine(dataDir, "git", "gitignore_global"), null);
        Directory.CreateDirectory(Path.Combine(dataDir, "shell"));
        Directory.CreateDirectory(Path.Combine(dataDir, "editors"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config"));
    }
}
