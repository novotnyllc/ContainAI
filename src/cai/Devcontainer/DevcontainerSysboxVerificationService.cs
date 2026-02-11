namespace ContainAI.Cli.Host;

internal interface IDevcontainerSysboxVerificationService
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);
}

internal sealed class DevcontainerSysboxVerificationService(
    IDevcontainerProcessHelpers processHelpers,
    TextWriter standardOutput,
    TextWriter standardError) : IDevcontainerSysboxVerificationService
{
    public async Task<int> VerifySysboxAsync(CancellationToken cancellationToken)
    {
        var passed = 0;
        var sysboxfsFound = false;
        await WriteHeaderAsync(standardOutput).ConfigureAwait(false);

        if (await CheckSysboxFsAsync(processHelpers, standardOutput, cancellationToken).ConfigureAwait(false))
        {
            sysboxfsFound = true;
            passed++;
        }

        if (await CheckUidMappingAsync(processHelpers, standardOutput, cancellationToken).ConfigureAwait(false))
        {
            passed++;
        }

        if (await CheckNestedUserNamespaceAsync(processHelpers, standardOutput, cancellationToken).ConfigureAwait(false))
        {
            passed++;
        }

        if (await CheckCapabilitiesAsync(processHelpers, standardOutput, cancellationToken).ConfigureAwait(false))
        {
            passed++;
        }

        await standardOutput.WriteLineAsync($"\nPassed: {passed} checks").ConfigureAwait(false);
        if (!sysboxfsFound || passed < 3)
        {
            await standardError.WriteLineAsync("FAIL: sysbox verification failed").ConfigureAwait(false);
            return 1;
        }

        await standardOutput.WriteLineAsync("[OK] Running in sysbox sandbox").ConfigureAwait(false);
        return 0;
    }

    private static async Task WriteHeaderAsync(TextWriter standardOutput)
    {
        await standardOutput.WriteLineAsync("ContainAI Sysbox Verification").ConfigureAwait(false);
        await standardOutput.WriteLineAsync("--------------------------------").ConfigureAwait(false);
    }

    private static async Task<bool> CheckSysboxFsAsync(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        CancellationToken cancellationToken)
    {
        if (await processHelpers.IsSysboxFsMountedAsync(cancellationToken).ConfigureAwait(false))
        {
            await standardOutput.WriteLineAsync("  [OK] Sysboxfs: mounted (REQUIRED)").ConfigureAwait(false);
            return true;
        }

        await standardOutput.WriteLineAsync("  [FAIL] Sysboxfs: not found (REQUIRED)").ConfigureAwait(false);
        return false;
    }

    private static async Task<bool> CheckUidMappingAsync(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        CancellationToken cancellationToken)
    {
        if (await processHelpers.HasUidMappingIsolationAsync(cancellationToken).ConfigureAwait(false))
        {
            await standardOutput.WriteLineAsync("  [OK] UID mapping: sysbox user namespace").ConfigureAwait(false);
            return true;
        }

        await standardOutput.WriteLineAsync("  [FAIL] UID mapping: 0->0 (not sysbox)").ConfigureAwait(false);
        return false;
    }

    private static async Task<bool> CheckNestedUserNamespaceAsync(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        CancellationToken cancellationToken)
    {
        if (await processHelpers.CommandSucceedsAsync("unshare", ["--user", "--map-root-user", "true"], cancellationToken).ConfigureAwait(false))
        {
            await standardOutput.WriteLineAsync("  [OK] Nested userns: allowed").ConfigureAwait(false);
            return true;
        }

        await standardOutput.WriteLineAsync("  [FAIL] Nested userns: blocked").ConfigureAwait(false);
        return false;
    }

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
