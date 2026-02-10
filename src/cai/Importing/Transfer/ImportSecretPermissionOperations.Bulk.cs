namespace ContainAI.Cli.Host;

internal sealed partial class ImportSecretPermissionOperations
{
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
}
