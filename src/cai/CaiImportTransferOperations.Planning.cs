using System.Text;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportTransferOperations
{
    private readonly record struct ManifestImportPlan(
        string SourceAbsolutePath,
        bool SourceExists,
        bool IsDirectory,
        string NormalizedSource,
        string NormalizedTarget);

    private async Task<int> InitializeImportTargetsCoreAsync(
        string volume,
        string sourceRoot,
        IReadOnlyList<ManifestEntry> entries,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            if (ShouldSkipForNoSecrets(entry, noSecrets))
            {
                continue;
            }

            var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
            var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
            var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
            var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            if (isDirectory)
            {
                var ensureDirectory = await DockerCaptureAsync(
                    ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureDirectoryCommand(entry.Target, IsSecretEntry(entry))],
                    cancellationToken).ConfigureAwait(false);
                if (ensureDirectory.ExitCode != 0)
                {
                    await stderr.WriteLineAsync(ensureDirectory.StandardError.Trim()).ConfigureAwait(false);
                    return 1;
                }

                continue;
            }

            if (!isFile)
            {
                continue;
            }

            if (entry.Optional && !sourceExists)
            {
                continue;
            }

            var ensureFile = await DockerCaptureAsync(
                ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureFileCommand(entry)],
                cancellationToken).ConfigureAwait(false);
            if (ensureFile.ExitCode != 0)
            {
                await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
                return 1;
            }
        }

        return 0;
    }

    private static ManifestImportPlan CreateManifestImportPlan(string sourceRoot, ManifestEntry entry)
    {
        var sourceAbsolutePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourceAbsolutePath) || File.Exists(sourceAbsolutePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal) && Directory.Exists(sourceAbsolutePath);
        return new(
            sourceAbsolutePath,
            sourceExists,
            isDirectory,
            NormalizeManifestPath(entry.Source),
            NormalizeManifestPath(entry.Target));
    }

    private static string NormalizeManifestPath(string path)
        => path.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');

    private static string BuildEnsureDirectoryCommand(string targetPath, bool isSecret)
    {
        var escapedTarget = EscapeForSingleQuotedShell(targetPath);
        var command = $"mkdir -p '/mnt/agent-data/{escapedTarget}' && chown -R 1000:1000 '/mnt/agent-data/{escapedTarget}' || true";
        if (isSecret)
        {
            command += $" && chmod 700 '/mnt/agent-data/{escapedTarget}'";
        }

        return command;
    }

    private static string BuildEnsureFileCommand(ManifestEntry entry)
    {
        var ensureFileCommand = new StringBuilder();
        ensureFileCommand.Append($"dest='/mnt/agent-data/{EscapeForSingleQuotedShell(entry.Target)}'; ");
        ensureFileCommand.Append("mkdir -p \"$(dirname \"$dest\")\"; ");
        ensureFileCommand.Append("if [ ! -f \"$dest\" ]; then : > \"$dest\"; fi; ");
        if (entry.Flags.Contains('j', StringComparison.Ordinal))
        {
            ensureFileCommand.Append("if [ ! -s \"$dest\" ]; then printf '{}' > \"$dest\"; fi; ");
        }

        ensureFileCommand.Append("chown 1000:1000 \"$dest\" || true; ");
        if (IsSecretEntry(entry))
        {
            ensureFileCommand.Append("chmod 600 \"$dest\"; ");
        }

        return ensureFileCommand.ToString();
    }
}
