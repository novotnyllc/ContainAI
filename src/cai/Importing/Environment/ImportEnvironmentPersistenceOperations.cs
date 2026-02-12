using System.Text;
using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Environment;

internal sealed class ImportEnvironmentPersistenceOperations : IImportEnvironmentPersistenceOperations
{
    private readonly TextWriter stderr;

    public ImportEnvironmentPersistenceOperations(TextWriter standardOutput, TextWriter standardError)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
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

        var writeCommand = $"set -e; target='/mnt/agent-data/.env'; if [ -L \"$target\" ]; then echo '{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(CaiImportEnvironmentOperations.EnvTargetSymlinkGuardMessage)}' >&2; exit 1; fi; " +
                           "tmp='/mnt/agent-data/.env.tmp'; cat > \"$tmp\"; chmod 600 \"$tmp\"; chown 1000:1000 \"$tmp\" || true; mv -f \"$tmp\" \"$target\"";
        var write = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
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
