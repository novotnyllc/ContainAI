namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportOverrideTransferOperations
{
    private async Task<int> CopyPreparedOverrideAsync(
        string volume,
        string overridesDirectory,
        PreparedOverride preparedOverride,
        CancellationToken cancellationToken)
    {
        var copy = await DockerCaptureAsync(
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
        if (copy.ExitCode != 0)
        {
            await stderr.WriteLineAsync(copy.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
