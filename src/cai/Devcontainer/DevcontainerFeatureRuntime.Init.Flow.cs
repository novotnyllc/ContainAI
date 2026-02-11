namespace ContainAI.Cli.Host;

internal sealed partial class DevcontainerFeatureInitWorkflow
{
    public async Task<int> RunInitAsync(CancellationToken cancellationToken)
    {
        var settings = await configLoader.LoadFeatureConfigOrWriteErrorAsync(cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            return 1;
        }

        var verifyCode = await serviceBootstrap.VerifySysboxAsync(cancellationToken).ConfigureAwait(false);
        if (verifyCode != 0)
        {
            return verifyCode;
        }

        var userHome = await userEnvironmentSetup.DetectUserHomeAsync(settings.RemoteUser, cancellationToken).ConfigureAwait(false);
        await stdout.WriteLineAsync($"ContainAI init: Setting up symlinks in {userHome}").ConfigureAwait(false);

        var linkSpec = await linkSpecLoader.LoadLinkSpecForInitAsync(cancellationToken).ConfigureAwait(false);
        if (linkSpec is null)
        {
            return 0;
        }

        var result = await linkApplier.ApplyLinksAsync(linkSpec, settings, userHome, cancellationToken).ConfigureAwait(false);
        await WriteInitSummaryAsync(result).ConfigureAwait(false);
        return 0;
    }

    private async Task WriteInitSummaryAsync(DevcontainerFeatureLinkApplyResult result)
    {
        await stdout.WriteAsync($"\nContainAI init complete: {result.Created} symlinks created").ConfigureAwait(false);
        if (result.Skipped > 0)
        {
            await stdout.WriteAsync($", {result.Skipped} credential files skipped").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync().ConfigureAwait(false);
    }
}
