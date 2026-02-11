using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportOverrideCopyExecutor
{
    private readonly TextWriter stderr;

    public ImportOverrideCopyExecutor(TextWriter standardError)
        => stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));

    public async Task<int> CopyAsync(
        string volume,
        string overridesDirectory,
        ImportPreparedOverride preparedOverride,
        CancellationToken cancellationToken)
    {
        var copy = await CaiRuntimeDockerHelpers.DockerCaptureAsync(
            [
                "run",
                "--rm",
                "-v",
                $"{volume}:/target",
                "-v",
                $"{overridesDirectory}:/override:ro",
                "alpine:3.20",
                "sh",
                "-lc",
                BuildOverrideCopyCommand(preparedOverride.RelativePath, preparedOverride.MappedTargetPath),
            ],
            cancellationToken).ConfigureAwait(false);

        if (copy.ExitCode == 0)
        {
            return 0;
        }

        await stderr.WriteLineAsync(copy.StandardError.Trim()).ConfigureAwait(false);
        return 1;
    }

    private static string BuildOverrideCopyCommand(string relativePath, string mappedTargetPath)
        => $"src='/override/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(relativePath.TrimStart('/'))}'; " +
           $"dest='/target/{CaiRuntimePathHelpers.EscapeForSingleQuotedShell(mappedTargetPath)}'; " +
           "mkdir -p \"$(dirname \"$dest\")\"; cp -f \"$src\" \"$dest\"; chown 1000:1000 \"$dest\" || true";
}
