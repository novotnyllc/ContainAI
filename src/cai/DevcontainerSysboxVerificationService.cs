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
        await standardOutput.WriteLineAsync("ContainAI Sysbox Verification").ConfigureAwait(false);
        await standardOutput.WriteLineAsync("--------------------------------").ConfigureAwait(false);

        if (await processHelpers.IsSysboxFsMountedAsync(cancellationToken).ConfigureAwait(false))
        {
            sysboxfsFound = true;
            passed++;
            await standardOutput.WriteLineAsync("  [OK] Sysboxfs: mounted (REQUIRED)").ConfigureAwait(false);
        }
        else
        {
            await standardOutput.WriteLineAsync("  [FAIL] Sysboxfs: not found (REQUIRED)").ConfigureAwait(false);
        }

        if (await processHelpers.HasUidMappingIsolationAsync(cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await standardOutput.WriteLineAsync("  [OK] UID mapping: sysbox user namespace").ConfigureAwait(false);
        }
        else
        {
            await standardOutput.WriteLineAsync("  [FAIL] UID mapping: 0->0 (not sysbox)").ConfigureAwait(false);
        }

        if (await processHelpers.CommandSucceedsAsync("unshare", ["--user", "--map-root-user", "true"], cancellationToken).ConfigureAwait(false))
        {
            passed++;
            await standardOutput.WriteLineAsync("  [OK] Nested userns: allowed").ConfigureAwait(false);
        }
        else
        {
            await standardOutput.WriteLineAsync("  [FAIL] Nested userns: blocked").ConfigureAwait(false);
        }

        var tempDirectory = Path.Combine(Path.GetTempPath(), $"containai-sysbox-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);
        var mountSucceeded = await processHelpers.CommandSucceedsAsync("mount", ["-t", "tmpfs", "none", tempDirectory], cancellationToken).ConfigureAwait(false);
        if (mountSucceeded)
        {
            _ = await processHelpers.CommandSucceedsAsync("umount", [tempDirectory], cancellationToken).ConfigureAwait(false);
            passed++;
            await standardOutput.WriteLineAsync("  [OK] Capabilities: CAP_SYS_ADMIN works").ConfigureAwait(false);
        }
        else
        {
            await standardOutput.WriteLineAsync("  [FAIL] Capabilities: mount denied").ConfigureAwait(false);
        }

        try
        {
            Directory.Delete(tempDirectory, recursive: true);
        }
        catch (IOException ex)
        {
            _ = ex;
        }
        catch (UnauthorizedAccessException ex)
        {
            _ = ex;
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
}
