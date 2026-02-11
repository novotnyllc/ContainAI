namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureLinkDestinationPreparer
{
    private readonly TextWriter stderr;
    private readonly IDevcontainerProcessHelpers processHelpers;

    public DevcontainerFeatureLinkDestinationPreparer(TextWriter standardError, IDevcontainerProcessHelpers devcontainerProcessHelpers)
    {
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        processHelpers = devcontainerProcessHelpers ?? throw new ArgumentNullException(nameof(devcontainerProcessHelpers));
    }

    public async Task<bool> PrepareDestinationAsync(string rewrittenLink, bool removeFirst)
    {
        if (Directory.Exists(rewrittenLink) && !processHelpers.IsSymlink(rewrittenLink))
        {
            if (!removeFirst)
            {
                await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                return false;
            }

            Directory.Delete(rewrittenLink, recursive: true);
            return true;
        }

        if (File.Exists(rewrittenLink) || processHelpers.IsSymlink(rewrittenLink))
        {
            File.Delete(rewrittenLink);
        }

        return true;
    }

    public static void CreateSymbolicLink(string rewrittenLink, string target)
    {
        if (Directory.Exists(target))
        {
            Directory.CreateSymbolicLink(rewrittenLink, target);
        }
        else
        {
            File.CreateSymbolicLink(rewrittenLink, target);
        }
    }
}
