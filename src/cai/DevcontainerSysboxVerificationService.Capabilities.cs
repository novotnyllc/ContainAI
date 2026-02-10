namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerSysboxVerificationService
{
    private static async Task<bool> CheckCapabilitiesAsync(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        CancellationToken cancellationToken)
    {
        var tempDirectory = Path.Combine(Path.GetTempPath(), $"containai-sysbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);

        var mountSucceeded = await processHelpers
            .CommandSucceedsAsync("mount", ["-t", "tmpfs", "none", tempDirectory], cancellationToken)
            .ConfigureAwait(false);

        if (mountSucceeded)
        {
            _ = await processHelpers.CommandSucceedsAsync("umount", [tempDirectory], cancellationToken).ConfigureAwait(false);
            await standardOutput.WriteLineAsync("  [OK] Capabilities: CAP_SYS_ADMIN works").ConfigureAwait(false);
            TryDeleteDirectory(tempDirectory);
            return true;
        }

        await standardOutput.WriteLineAsync("  [FAIL] Capabilities: mount denied").ConfigureAwait(false);
        TryDeleteDirectory(tempDirectory);
        return false;
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
