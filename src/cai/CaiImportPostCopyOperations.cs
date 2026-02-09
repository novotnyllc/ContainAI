using System.Text;

namespace ContainAI.Cli.Host;

internal interface IImportPostCopyOperations
{
    Task<int> EnforceSecretPathPermissionsAsync(
        string volume,
        IReadOnlyList<ManifestEntry> manifestEntries,
        bool noSecrets,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}

internal sealed class CaiImportPostCopyOperations : CaiRuntimeSupport
    , IImportPostCopyOperations
{
    public CaiImportPostCopyOperations(TextWriter standardOutput, TextWriter standardError)
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

        if (secretDirectories.Count == 0 && secretFiles.Count == 0)
        {
            return 0;
        }

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

        var result = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", commandBuilder.ToString()],
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

    public async Task<int> ApplyManifestPostCopyRulesAsync(
        string volume,
        ManifestEntry entry,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (dryRun)
        {
            return 0;
        }

        var normalizedTarget = entry.Target.Replace("\\", "/", StringComparison.Ordinal).TrimStart('/');
        if (entry.Flags.Contains('g', StringComparison.Ordinal))
        {
            var gitFilterCode = await ApplyGitConfigFilterAsync(volume, normalizedTarget, verbose, cancellationToken).ConfigureAwait(false);
            if (gitFilterCode != 0)
            {
                return gitFilterCode;
            }
        }

        if (!entry.Flags.Contains('s', StringComparison.Ordinal))
        {
            return 0;
        }

        var chmodMode = entry.Flags.Contains('d', StringComparison.Ordinal) ? "700" : "600";
        var chmodCommand = $"target='/target/{EscapeForSingleQuotedShell(normalizedTarget)}'; " +
                           "if [ -e \"$target\" ]; then chmod " + chmodMode + " \"$target\"; fi; " +
                           "if [ -e \"$target\" ]; then chown 1000:1000 \"$target\" || true; fi";
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

    private async Task<int> ApplyGitConfigFilterAsync(
        string volume,
        string targetRelativePath,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var filterScript = $"target='/target/{EscapeForSingleQuotedShell(targetRelativePath)}'; " +
                           "if [ ! -f \"$target\" ]; then exit 0; fi; " +
                           "tmp=\"$target.tmp\"; " +
                           "awk '\n" +
                           "BEGIN { section=\"\" }\n" +
                           "/^[[:space:]]*\\[[^]]+\\][[:space:]]*$/ {\n" +
                           "  section=$0;\n" +
                           "  gsub(/^[[:space:]]*\\[/, \"\", section);\n" +
                           "  gsub(/\\][[:space:]]*$/, \"\", section);\n" +
                           "  section=tolower(section);\n" +
                           "  print $0;\n" +
                           "  next;\n" +
                           "}\n" +
                           "{\n" +
                           "  lower=tolower($0);\n" +
                           "  if (section==\"credential\" && lower ~ /^[[:space:]]*helper[[:space:]]*=/) next;\n" +
                           "  if ((section==\"commit\" || section==\"tag\") && lower ~ /^[[:space:]]*gpgsign[[:space:]]*=/) next;\n" +
                           "  if (section==\"gpg\" && (lower ~ /^[[:space:]]*program[[:space:]]*=/ || lower ~ /^[[:space:]]*format[[:space:]]*=/)) next;\n" +
                           "  if (section==\"user\" && lower ~ /^[[:space:]]*signingkey[[:space:]]*=/) next;\n" +
                           "  print $0;\n" +
                           "}\n" +
                           "' \"$target\" > \"$tmp\"; " +
                           "mv \"$tmp\" \"$target\"; " +
                           "if ! grep -Eiq \"^[[:space:]]*directory[[:space:]]*=[[:space:]]*/home/agent/workspace[[:space:]]*$\" \"$target\"; then " +
                           "  printf '\\n[safe]\\n\\tdirectory = /home/agent/workspace\\n' >> \"$target\"; " +
                           "fi; " +
                           "chown 1000:1000 \"$target\" || true";

        var filterResult = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/target", "alpine:3.20", "sh", "-lc", filterScript],
            cancellationToken).ConfigureAwait(false);
        if (filterResult.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(filterResult.StandardError))
            {
                await stderr.WriteLineAsync(filterResult.StandardError.Trim()).ConfigureAwait(false);
            }

            return 1;
        }

        if (verbose)
        {
            await stdout.WriteLineAsync($"[INFO] Applied git filter to {targetRelativePath}").ConfigureAwait(false);
        }

        return 0;
    }
}
