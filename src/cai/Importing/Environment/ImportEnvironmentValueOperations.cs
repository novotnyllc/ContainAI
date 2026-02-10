using System.Text;
using System.Text.Json;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed class ImportEnvironmentValueOperations : CaiRuntimeSupport
    , IImportEnvironmentValueOperations
{
    public ImportEnvironmentValueOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<List<string>> ResolveValidatedImportKeysAsync(JsonElement envSection, bool verbose, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var importKeys = new List<string>();
        if (!envSection.TryGetProperty("import", out var importArray))
        {
            await stderr.WriteLineAsync("[WARN] [env].import missing, treating as empty list").ConfigureAwait(false);
        }
        else if (importArray.ValueKind != JsonValueKind.Array)
        {
            await stderr.WriteLineAsync($"[WARN] [env].import must be a list, got {importArray.ValueKind}; treating as empty list").ConfigureAwait(false);
        }
        else
        {
            var itemIndex = 0;
            foreach (var value in importArray.EnumerateArray())
            {
                if (value.ValueKind == JsonValueKind.String)
                {
                    var key = value.GetString();
                    if (!string.IsNullOrWhiteSpace(key))
                    {
                        importKeys.Add(key);
                    }
                }
                else
                {
                    await stderr.WriteLineAsync($"[WARN] [env].import[{itemIndex}] must be a string, got {value.ValueKind}; skipping").ConfigureAwait(false);
                }

                itemIndex++;
            }
        }

        var dedupedImportKeys = new List<string>();
        var seenKeys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in importKeys)
        {
            if (seenKeys.Add(key))
            {
                dedupedImportKeys.Add(key);
            }
        }

        if (dedupedImportKeys.Count == 0)
        {
            if (verbose)
            {
                await stdout.WriteLineAsync("[INFO] Empty env allowlist, skipping env import").ConfigureAwait(false);
            }

            return [];
        }

        var validatedKeys = new List<string>(dedupedImportKeys.Count);
        foreach (var key in dedupedImportKeys)
        {
            if (!EnvVarNameRegex().IsMatch(key))
            {
                await stderr.WriteLineAsync($"[WARN] Invalid env var name in allowlist: {key}").ConfigureAwait(false);
                continue;
            }

            validatedKeys.Add(key);
        }

        return validatedKeys;
    }

    public async Task<Dictionary<string, string>?> ResolveFileVariablesAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var fileVariables = new Dictionary<string, string>(StringComparer.Ordinal);
        if (envSection.TryGetProperty("env_file", out var envFileElement) && envFileElement.ValueKind == JsonValueKind.String)
        {
            var envFile = envFileElement.GetString();
            if (!string.IsNullOrWhiteSpace(envFile))
            {
                var envFileResolution = ResolveEnvFilePath(workspaceRoot, envFile);
                if (envFileResolution.Error is not null)
                {
                    await stderr.WriteLineAsync(envFileResolution.Error).ConfigureAwait(false);
                    return null;
                }

                if (envFileResolution.Path is not null)
                {
                    var parsed = ParseEnvFile(envFileResolution.Path);
                    foreach (var warning in parsed.Warnings)
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    foreach (var (key, value) in parsed.Values)
                    {
                        if (validatedKeys.Contains(key))
                        {
                            fileVariables[key] = value;
                        }
                    }
                }
            }
        }

        return fileVariables;
    }

    public async Task<bool> ResolveFromHostFlagAsync(JsonElement envSection, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (envSection.TryGetProperty("from_host", out var fromHostElement))
        {
            if (fromHostElement.ValueKind == JsonValueKind.True)
            {
                return true;
            }

            if (fromHostElement.ValueKind != JsonValueKind.False)
            {
                await stderr.WriteLineAsync("[WARN] [env].from_host must be a boolean; using false").ConfigureAwait(false);
            }
        }

        return false;
    }

    public async Task<Dictionary<string, string>> MergeVariablesWithHostValuesAsync(
        Dictionary<string, string> fileVariables,
        IReadOnlyList<string> validatedKeys,
        bool fromHost,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var merged = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in fileVariables)
        {
            merged[key] = value;
        }

        if (!fromHost)
        {
            return merged;
        }

        foreach (var key in validatedKeys)
        {
            var envValue = System.Environment.GetEnvironmentVariable(key);
            if (envValue is null)
            {
                await stderr.WriteLineAsync($"[WARN] Missing host env var: {key}").ConfigureAwait(false);
                continue;
            }

            if (envValue.Contains('\n', StringComparison.Ordinal))
            {
                await stderr.WriteLineAsync($"[WARN] source=host: key '{key}' skipped (multiline value)").ConfigureAwait(false);
                continue;
            }

            merged[key] = envValue;
        }

        return merged;
    }

    public async Task<int> PersistMergedEnvironmentAsync(
        string volume,
        IReadOnlyList<string> validatedKeys,
        Dictionary<string, string> merged,
        CancellationToken cancellationToken)
    {
        var builder = new StringBuilder();
        foreach (var key in validatedKeys)
        {
            if (!merged.TryGetValue(key, out var value))
            {
                continue;
            }

            builder.Append(key);
            builder.Append('=');
            builder.Append(value);
            builder.Append('\n');
        }

        var writeCommand = $"set -e; target='/mnt/agent-data/.env'; if [ -L \"$target\" ]; then echo '{EscapeForSingleQuotedShell(CaiImportEnvironmentOperations.EnvTargetSymlinkGuardMessage)}' >&2; exit 1; fi; " +
                           "tmp='/mnt/agent-data/.env.tmp'; cat > \"$tmp\"; chmod 600 \"$tmp\"; chown 1000:1000 \"$tmp\" || true; mv -f \"$tmp\" \"$target\"";
        var write = await DockerCaptureAsync(
            ["run", "--rm", "-i", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", writeCommand],
            builder.ToString(),
            cancellationToken).ConfigureAwait(false);
        if (write.ExitCode != 0)
        {
            await stderr.WriteLineAsync(write.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
