namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed partial class ImportManifestCopyOperations
{
    private static string ResolveRsyncImage()
    {
        var configured = System.Environment.GetEnvironmentVariable("CONTAINAI_RSYNC_IMAGE");
        return string.IsNullOrWhiteSpace(configured) ? "instrumentisto/rsync-ssh" : configured;
    }
}
