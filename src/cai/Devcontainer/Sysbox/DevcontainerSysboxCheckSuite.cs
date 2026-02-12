namespace ContainAI.Cli.Host.Devcontainer.Sysbox;

internal static class DevcontainerSysboxCheckSuite
{
    public static Task WriteHeaderAsync(TextWriter standardOutput)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);

        return WriteHeaderCoreAsync(standardOutput);

        static async Task WriteHeaderCoreAsync(TextWriter output)
        {
            await output.WriteLineAsync("ContainAI Sysbox Verification").ConfigureAwait(false);
            await output.WriteLineAsync("--------------------------------").ConfigureAwait(false);
        }
    }

    public static async Task<bool> CheckSysboxFsAsync(
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

    public static async Task<bool> CheckUidMappingAsync(
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

    public static async Task<bool> CheckNestedUserNamespaceAsync(
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

    public static async Task<bool> CheckCapabilitiesAsync(
        IDevcontainerProcessHelpers processHelpers,
        TextWriter standardOutput,
        CancellationToken cancellationToken)
    {
        var mountSucceeded = await DevcontainerSysboxCapabilityProbe
            .CanMountTmpfsAsync(processHelpers, cancellationToken)
            .ConfigureAwait(false);

        if (mountSucceeded)
        {
            await standardOutput.WriteLineAsync("  [OK] Capabilities: CAP_SYS_ADMIN works").ConfigureAwait(false);
            return true;
        }

        await standardOutput.WriteLineAsync("  [FAIL] Capabilities: mount denied").ConfigureAwait(false);
        return false;
    }
}
