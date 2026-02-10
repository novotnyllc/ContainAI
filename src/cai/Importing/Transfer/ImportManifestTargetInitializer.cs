using System.Text;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestTargetInitializer
{
    Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken);
}

internal sealed class ImportManifestTargetInitializer : CaiRuntimeSupport
    , IImportManifestTargetInitializer
{
    public ImportManifestTargetInitializer(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> EnsureEntryTargetAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool noSecrets,
        CancellationToken cancellationToken)
    {
        if (ShouldSkipForNoSecrets(entry, noSecrets))
        {
            return 0;
        }

        var sourcePath = Path.GetFullPath(Path.Combine(sourceRoot, entry.Source));
        var sourceExists = Directory.Exists(sourcePath) || File.Exists(sourcePath);
        var isDirectory = entry.Flags.Contains('d', StringComparison.Ordinal);
        var isFile = entry.Flags.Contains('f', StringComparison.Ordinal);
        if (entry.Optional && !sourceExists)
        {
            return 0;
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

            return 0;
        }

        if (!isFile)
        {
            return 0;
        }

        var ensureFile = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", BuildEnsureFileCommand(entry)],
            cancellationToken).ConfigureAwait(false);
        if (ensureFile.ExitCode != 0)
        {
            await stderr.WriteLineAsync(ensureFile.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

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

    private static bool ShouldSkipForNoSecrets(ManifestEntry entry, bool noSecrets)
        => noSecrets && IsSecretEntry(entry);

    private static bool IsSecretEntry(ManifestEntry entry)
        => entry.Flags.Contains('s', StringComparison.Ordinal);
}
