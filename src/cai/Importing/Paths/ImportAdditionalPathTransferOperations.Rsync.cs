using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed partial class ImportAdditionalPathTransferOperations
{
    private static List<string> BuildRsyncArgs(string volume, ImportAdditionalPath additionalPath)
    {
        var rsyncArgs = new List<string>
        {
            "run",
            "--rm",
            "--entrypoint",
            "rsync",
            "-v",
            $"{volume}:/target",
            "-v",
            $"{additionalPath.SourcePath}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (additionalPath.ApplyPrivFilter)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (additionalPath.IsDirectory)
        {
            rsyncArgs.Add("/source/");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add("/source");
            rsyncArgs.Add($"/target/{additionalPath.TargetPath}");
        }

        return rsyncArgs;
    }

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
