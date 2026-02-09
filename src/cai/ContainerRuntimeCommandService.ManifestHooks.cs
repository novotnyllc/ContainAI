using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet)
    {
        await RunAsRootAsync("mkdir", ["-p", dataDir]).ConfigureAwait(false);
        await RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);

        if (Directory.Exists(manifestsDir))
        {
            await LogInfoAsync(quiet, "Applying init directory policy from manifests").ConfigureAwait(false);
            try
            {
                _ = ManifestApplier.ApplyInitDirs(manifestsDir, dataDir, manifestTomlParser);
            }
            catch (InvalidOperationException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (IOException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (UnauthorizedAccessException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (JsonException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (ArgumentException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
            catch (NotSupportedException ex)
            {
                await stderr.WriteLineAsync($"[WARN] Host init-dir apply failed, using fallback: {ex.Message}").ConfigureAwait(false);
                EnsureFallbackVolumeStructure(dataDir);
            }
        }
        else
        {
            await stderr.WriteLineAsync("[WARN] Built-in manifests not found, using fallback volume structure").ConfigureAwait(false);
            EnsureFallbackVolumeStructure(dataDir);
        }

        await RunAsRootAsync("chown", ["-R", "--no-dereference", "1000:1000", dataDir]).ConfigureAwait(false);
    }

    private static void EnsureFallbackVolumeStructure(string dataDir)
    {
        Directory.CreateDirectory(Path.Combine(dataDir, "claude"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config", "gh"));
        Directory.CreateDirectory(Path.Combine(dataDir, "git"));
        EnsureFileWithContent(Path.Combine(dataDir, "git", "gitconfig"), null);
        EnsureFileWithContent(Path.Combine(dataDir, "git", "gitignore_global"), null);
        Directory.CreateDirectory(Path.Combine(dataDir, "shell"));
        Directory.CreateDirectory(Path.Combine(dataDir, "editors"));
        Directory.CreateDirectory(Path.Combine(dataDir, "config"));
    }

    private async Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet)
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

        await LogInfoAsync(quiet, $"Found {manifestFiles.Length} user manifest(s), generating runtime configuration...").ConfigureAwait(false);
        try
        {
            _ = ManifestApplier.ApplyInitDirs(userManifestDirectory, dataDir, manifestTomlParser);
            _ = ManifestApplier.ApplyContainerLinks(userManifestDirectory, homeDir, dataDir, manifestTomlParser);
            _ = ManifestApplier.ApplyAgentShims(userManifestDirectory, "/opt/containai/user-agent-shims", "/usr/local/bin/cai", manifestTomlParser);

            var userSpec = ManifestGenerators.GenerateContainerLinkSpec(userManifestDirectory, manifestTomlParser);
            var userSpecPath = Path.Combine(dataDir, "containai", "user-link-spec.json");
            Directory.CreateDirectory(Path.GetDirectoryName(userSpecPath)!);
            await File.WriteAllTextAsync(userSpecPath, userSpec.Content).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (JsonException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            await stderr.WriteLineAsync($"[WARN] User manifest processing failed: {ex.Message}").ConfigureAwait(false);
        }
    }

    private async Task RunHooksAsync(
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
            if (!IsExecutable(hook))
            {
                await stderr.WriteLineAsync($"[WARN] Skipping non-executable hook: {hook}").ConfigureAwait(false);
                continue;
            }

            await LogInfoAsync(quiet, $"Running startup hook: {hook}").ConfigureAwait(false);
            var result = await RunProcessCaptureAsync(
                hook,
                [],
                workingDirectory,
                cancellationToken).ConfigureAwait(false);
            if (result.ExitCode != 0)
            {
                throw new InvalidOperationException($"Startup hook failed: {hook}: {result.StandardError.Trim()}");
            }
        }

        await LogInfoAsync(quiet, $"Completed hooks from: {hooksDirectory}").ConfigureAwait(false);
    }

    private static bool IsExecutable(string path)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                var extension = Path.GetExtension(path);
                return extension.Equals(".exe", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".bat", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".com", StringComparison.OrdinalIgnoreCase)
                    || extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase);
            }

            var mode = File.GetUnixFileMode(path);
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (PlatformNotSupportedException)
        {
            return false;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }
}
