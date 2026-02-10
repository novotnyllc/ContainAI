namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerSysboxVerificationService
{
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
}
