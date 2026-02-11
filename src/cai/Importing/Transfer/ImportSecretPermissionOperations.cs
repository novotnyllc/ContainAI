using System.Text;

namespace ContainAI.Cli.Host;

internal interface IImportSecretPermissionOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyEntrySecretPermissionsAsync(
        string volume,
        string normalizedTarget,
        bool isDirectory,
        CancellationToken cancellationToken);
}

internal sealed class ImportSecretPermissionOperations : CaiRuntimeSupport
    , IImportSecretPermissionOperations
{
    public ImportSecretPermissionOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var (secretDirectories, secretFiles) = CollectSecretPaths(manifestEntries, noSecrets);

        if (secretDirectories.Count == 0 && secretFiles.Count == 0)
        {
            return 0;
        }

        var permissionsCommand = BuildBulkPermissionsCommand(secretDirectories, secretFiles);

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", permissionsCommand],
            cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync("[INFO] Enforced secret path permissions").ConfigureAwait(false);
        }

        return 0;
    }

    public async Task<int> ApplyEntrySecretPermissionsAsync(
        string volume,
        string normalizedTarget,
        bool isDirectory,
        CancellationToken cancellationToken)
    {
        var chmodCommand = BuildEntryPermissionsCommand(normalizedTarget, isDirectory);
        var chmodResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", chmodCommand],
            cancellationToken).ConfigureAwait(false);
        if (chmodResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(chmodResult.StandardError))
            {
                await stderr.WriteLineAsync(chmodResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        return 0;
    }

    private static (HashSet<string> SecretDirectories, HashSet<string> SecretFiles) CollectSecretPaths(
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets)
    {
        var secretDirectories = new HashSet<string>(StringComparer.Ordinal);
        var secretFiles = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in manifestEntries)
        {
            if (!entry.Flags.Contains('s', StringComparison.Ordinal) || noSecrets)
            {
                continue;
            }

            var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                secretDirectories.Add(normalizedTarget);
                continue;
            }

            secretFiles.Add(normalizedTarget);
            var parent = Path.GetDirectoryName(normalizedTarget)?.Replace("\\", "/", StringComparison.Ordinal);
            if (!string.IsNullOrWhiteSpace(parent))
            {
                secretDirectories.Add(parent);
            }
        }

        return (secretDirectories, secretFiles);
    }

    private static string BuildBulkPermissionsCommand(HashSet<string> secretDirectories, HashSet<string> secretFiles)
    {
        var commandBuilder = new StringBuilder();
        foreach (var directory in secretDirectories.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -d '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' ]; then chmod 700 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(directory));
            commandBuilder.Append("' || true; fi; ");
        }

        foreach (var file in secretFiles.OrderBy(static value => value, StringComparer.Ordinal))
        {
            commandBuilder.Append("if [ -f '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' ]; then chmod 600 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("'; chown 1000:1000 '/target/");
            commandBuilder.Append(EscapeForSingleQuotedShell(file));
            commandBuilder.Append("' || true; fi; ");
        }

        return commandBuilder.ToString();
    }

    private static string BuildEntryPermissionsCommand(string normalizedTarget, bool isDirectory)
    {
        var chmodMode = isDirectory ? "700" : "600";
        return $"target='/target/{EscapeForSingleQuotedShell(normalizedTarget)}'; " +
               "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
               "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
    }
}
