namespace ContainAI.Cli.Host;

internal static class InstallCommandErrorHandler
{
    public static async Task<int> WriteErrorAndReturnAsync(
        IInstallCommandOutput output,
        string message,
        CancellationToken cancellationToken)
    {
        await output.WriteErrorAsync(message, cancellationToken).ConfigureAwait(false);
        return 1;
    }
}
