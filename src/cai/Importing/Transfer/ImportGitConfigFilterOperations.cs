using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal sealed class ImportGitConfigFilterOperations : IImportGitConfigFilterOperations
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;

    public ImportGitConfigFilterOperations(TextWriter standardOutput, TextWriter standardError)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task<int> ApplyGitConfigFilterAsync(
        string volume,
        string targetRelativePath,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var filterScript = $"target='/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(targetRelativePath)}'; " +
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

        var filterResult = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
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
