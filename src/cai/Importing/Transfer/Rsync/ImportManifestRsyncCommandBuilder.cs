namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestRsyncCommandBuilder
{
    List<string> Build(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan);
}

internal sealed class ImportManifestRsyncCommandBuilder : IImportManifestRsyncCommandBuilder
{
    public List<string> Build(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan)
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
            $"{sourceRoot}:/source:ro",
            ResolveRsyncImage(),
            "-a",
        };

        if (entry.Flags.Contains('m', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--delete");
        }

        if (!noExcludes && entry.Flags.Contains('x', StringComparison.Ordinal))
        {
            rsyncArgs.Add("--exclude=.system/");
        }

        if (!noExcludes && entry.Flags.Contains('p', StringComparison.Ordinal) && excludePriv)
        {
            rsyncArgs.Add("--exclude=*.priv.*");
        }

        if (importPlan.IsDirectory)
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource.TrimEnd('/')}/");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget.TrimEnd('/')}/");
        }
        else
        {
            rsyncArgs.Add($"/source/{importPlan.NormalizedSource}");
            rsyncArgs.Add($"/target/{importPlan.NormalizedTarget}");
        }

        return rsyncArgs;
    }

    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
