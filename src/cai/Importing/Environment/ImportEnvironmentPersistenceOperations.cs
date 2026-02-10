using System.Text;

namespace ContainAI.Cli.Host.Importing.Environment;

internal interface IImportEnvironmentPersistenceOperations
{
    Task<int> PersistMergedEnvironmentAsync(
        string volume,
        IReadOnlyList<string> validatedKeys,
        Dictionary<string, string> merged,
        CancellationToken cancellationToken);
}

internal sealed class ImportEnvironmentPersistenceOperations : CaiRuntimeSupport
    , IImportEnvironmentPersistenceOperations
{
    public ImportEnvironmentPersistenceOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
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
