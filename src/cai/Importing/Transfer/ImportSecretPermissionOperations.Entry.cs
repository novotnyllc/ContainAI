namespace ContainAI.Cli.Host;

internal sealed partial class ImportSecretPermissionOperations
{
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
}
