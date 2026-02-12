namespace ContainAI.Cli.Host.Devcontainer.Sysbox;

internal static class DevcontainerSysboxCapabilityProbe
{
    public static async Task<bool> CanMountTmpfsAsync(IDevcontainerProcessHelpers processHelpers, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(processHelpers);

        var tempDirectory = Path.Combine(Path.GetTempPath(), $"containai-sysbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);

        var mountSucceeded = await processHelpers
            .CommandSucceedsAsync("mount", ["-t", "tmpfs", "none", tempDirectory], cancellationToken)
            .ConfigureAwait(false);

        if (mountSucceeded)
        {
            _ = await processHelpers.CommandSucceedsAsync("umount", [tempDirectory], cancellationToken).ConfigureAwait(false);
        }

        TryDeleteDirectory(tempDirectory);
        return mountSucceeded;
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            Directory.Delete(path, recursive: true);
        }
        catch (IOException ex)
        {
            _ = ex;
        }
        catch (UnauthorizedAccessException ex)
        {
            _ = ex;
        }
    }
}
