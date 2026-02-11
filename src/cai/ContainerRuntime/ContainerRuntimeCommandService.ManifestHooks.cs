using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeManifestBootstrapService
{
    Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet);

    Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet);

    Task RunHooksAsync(string hooksDirectory, string workspaceDirectory, string homeDirectory, bool quiet, CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimeManifestBootstrapService : IContainerRuntimeManifestBootstrapService
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IManifestApplier manifestApplier;

    public ContainerRuntimeManifestBootstrapService(IContainerRuntimeExecutionContext context)
        : this(context, new ManifestApplier(context?.ManifestTomlParser ?? throw new ArgumentNullException(nameof(context))))
    {
    }

    internal ContainerRuntimeManifestBootstrapService(
        IContainerRuntimeExecutionContext context,
        IManifestApplier manifestApplier)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.manifestApplier = manifestApplier ?? throw new ArgumentNullException(nameof(manifestApplier));
    }

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

    public async Task RunHooksAsync(
        string hooksDirectory,
        string workspaceDirectory,
        string homeDirectory,
        bool quiet,
        CancellationToken cancellationToken)
    {
        if (!Directory.Exists(hooksDirectory))
        {
            return;
        }

        var hooks = Directory.EnumerateFiles(hooksDirectory, "*.sh", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        if (hooks.Length == 0)
        {
            return;
        }

        var workingDirectory = Directory.Exists(workspaceDirectory) ? workspaceDirectory : homeDirectory;
        foreach (var hook in hooks)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!context.IsExecutable(hook))
            {
                await context.StandardError.WriteLineAsync($"[WARN] Skipping non-executable hook: {hook}").ConfigureAwait(false);
                continue;
            }

            await context.LogInfoAsync(quiet, $"Running startup hook: {hook}").ConfigureAwait(false);
            var result = await context.RunProcessCaptureAsync(
                hook,
                [],
                workingDirectory,
                cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException($"Startup hook failed: {hook}: {result.StandardError.Trim()}");
            }
        }

        await context.LogInfoAsync(quiet, $"Completed hooks from: {hooksDirectory}").ConfigureAwait(false);
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
