namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureInitLinkApplier
{
    private async Task<bool> PrepareDestinationAsync(string rewrittenLink, bool removeFirst)
    {
        if (Directory.Exists(rewrittenLink) && !processHelpers.IsSymlink(rewrittenLink))
        {
            if (!removeFirst)
            {
                await stderr.WriteLineAsync($"  [FAIL] {rewrittenLink} (directory exists, remove_first not set)").ConfigureAwait(false);
                return false;
            }

            Directory.Delete(rewrittenLink, recursive: true);
        }
        else if (File.Exists(rewrittenLink) || processHelpers.IsSymlink(rewrittenLink))
        {
            File.Delete(rewrittenLink);
        }

        return true;
    }

    private static void CreateSymbolicLink(string rewrittenLink, string target)
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
