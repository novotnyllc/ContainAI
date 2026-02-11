namespace ContainAI.Cli.Host;

internal interface IDevcontainerSysboxVerificationService
{
    Task<int> VerifySysboxAsync(CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerSysboxVerificationService(
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
}
