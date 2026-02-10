namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportArchiveTransferOperations : CaiRuntimeSupport
    , IImportArchiveTransferOperations
{
    public ImportArchiveTransferOperations(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<int> RestoreArchiveImportAsync(string volume, string archivePath, bool excludePriv, CancellationToken cancellationToken)
    {
        var clear = await DockerCaptureAsync(
            ["run", "--rm", "-v", $"{volume}:/mnt/agent-data", "alpine:3.20", "sh", "-lc", "find /mnt/agent-data -mindepth 1 -delete"],
            cancellationToken).ConfigureAwait(false);
        if (clear.ExitCode != 0)
        {
            await stderr.WriteLineAsync(clear.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        var archiveDirectory = Path.GetDirectoryName(archivePath)!;
        var archiveName = Path.GetFileName(archivePath);
        var extractArgs = new List<string>
        {
            "run",
            "--rm",
            "-v",
            $"{volume}:/mnt/agent-data",
            "-v",
            $"{archiveDirectory}:/backup:ro",
            "alpine:3.20",
            "tar",
        };
        if (excludePriv)
        {
            extractArgs.Add("--exclude=./shell/bashrc.d/*.priv.*");
            extractArgs.Add("--exclude=shell/bashrc.d/*.priv.*");
        }

        extractArgs.Add("-xzf");
        extractArgs.Add($"/backup/{archiveName}");
        extractArgs.Add("-C");
        extractArgs.Add("/mnt/agent-data");

        var extract = await DockerCaptureAsync(extractArgs, cancellationToken).ConfigureAwait(false);
        if (extract.ExitCode != 0)
        {
            await stderr.WriteLineAsync(extract.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }
}
