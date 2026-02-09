using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
    public async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("import", out var importElement) ||
                importElement.ValueKind != JsonValueKind.Object ||
                !importElement.TryGetProperty("additional_paths", out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            var values = new List<ImportAdditionalPath>();
            var seenSources = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in pathsElement.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String)
                {
                    await stderr.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                    continue;
                }

                var rawPath = item.GetString();
                if (!TryResolveAdditionalImportPath(rawPath, sourceRoot, excludePriv, out var resolved, out var warning))
                {
                    if (!string.IsNullOrWhiteSpace(warning))
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    continue;
                }

                if (!seenSources.Add(resolved.SourcePath))
                {
                    continue;
                }

                values.Add(resolved);
            }

            return values;
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }

    public async Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            await stdout.WriteLineAsync($"[DRY-RUN] Would sync additional path {additionalPath.SourcePath} -> {additionalPath.TargetPath}").ConfigureAwait(false);
            return 0;
        }

        if (verbose && noExcludes)
        {
            await stdout.WriteLineAsync("[INFO] --no-excludes does not disable .priv. filtering for additional paths").ConfigureAwait(false);
        }

        var ensureCommand = additionalPath.IsDirectory
            ? $"mkdir -p '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}'"
            : $"mkdir -p \"$(dirname '/target/{EscapeForSingleQuotedShell(additionalPath.TargetPath)}')\"";
        var ensureResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", ensureCommand],
            cancellationToken).ConfigureAwait(false);
        if (ensureResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(ensureResult.StandardError))
            {
                await stderr.WriteLineAsync(ensureResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{additionalPath.SourcePath}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (additionalPath.ApplyPrivFilter)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (additionalPath.IsDirectory)
        {
            rsyncArgs.Add("/source/");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add("/source");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath}");
        }

        var result = await DockerCaptureAsync(rsyncArgs, cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            var errorOutput = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
            var normalizedError = errorOutput.Trim();
            if (normalizedError.Contains("could not make way for new symlink", StringComparison.OrdinalIgnoreCase) &&
                !normalizedError.Contains("cannot delete non-empty directory", StringComparison.OrdinalIgnoreCase))
            {
                normalizedError += $"{Environment.NewLine}cannot delete non-empty directory";
            }

            await stderr.WriteLineAsync(normalizedError).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private static bool TryResolveAdditionalImportPath(
        string? rawPath,
        string sourceRoot,
        bool excludePriv,
        out ImportAdditionalPath resolved,
        out string? warning)
    {
        resolved = default;

        if (!TryValidateAdditionalPathEntry(rawPath, out warning))
        {
            return false;
        }

        var validatedRawPath = rawPath!;
        if (!TryResolveNormalizedAdditionalPath(validatedRawPath, sourceRoot, out var effectiveHome, out var fullPath, out warning))
        {
            return false;
        }

        if (!TryValidateAdditionalPathBoundaries(validatedRawPath, effectiveHome, fullPath, out warning))
        {
            return false;
        }

        var targetRelativePath = MapAdditionalPathTarget(effectiveHome, fullPath);
        if (string.IsNullOrWhiteSpace(targetRelativePath))
        {
            warning = $"[WARN] [import].additional_paths '{validatedRawPath}' resolved to an empty target; skipping";
            return false;
        }

        var isDirectory = Directory.Exists(fullPath);
        var applyPrivFilter = excludePriv && IsBashrcDirectoryPath(effectiveHome, fullPath);
        resolved = new ImportAdditionalPath(fullPath, targetRelativePath, isDirectory, applyPrivFilter);
        warning = null;
        return true;
    }

    private static string ResolveRsyncImage()
    {
        var configured = Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
