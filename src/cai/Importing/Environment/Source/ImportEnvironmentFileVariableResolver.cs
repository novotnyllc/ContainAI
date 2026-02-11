using System.Text.Json;
using ContainAI.Cli.Host.RuntimeSupport.Environment;

namespace ContainAI.Cli.Host.Importing.Environment.Source;

internal interface IImportEnvironmentFileVariableResolver
{
    Task<Dictionary<string, string>?> ResolveAsync(
        JsonElement envSection,
        string workspaceRoot,
        IReadOnlyCollection<string> validatedKeys,
        CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentFileVariableResolver : IImportEnvironmentFileVariableResolver
{
    private readonly TextWriter stderr;

    public ImportEnvironmentFileVariableResolver(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<Dictionary<string, string>?> ResolveAsync(
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
                var envFileResolution = CaiRuntimeEnvFileHelpers.ResolveEnvFilePath(workspaceRoot, envFile);
                if (envFileResolution.Error is not null)
                {
                    await stderr.WriteLineAsync(envFileResolution.Error).ConfigureAwait(false);
                    return null;
                }

                if (envFileResolution.Path is not null)
                {
                    var parsed = CaiRuntimeEnvFileHelpers.ParseEnvFile(envFileResolution.Path);
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
}
