namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureStartWorkflow : IDevcontainerFeatureStartWorkflow
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IDevcontainerServiceBootstrap serviceBootstrap;
    private readonly IDevcontainerFeatureConfigLoader configLoader;

    public DevcontainerFeatureStartWorkflow(
        TextWriter stdout,
        TextWriter stderr,
        IDevcontainerServiceBootstrap serviceBootstrap,
        IDevcontainerFeatureConfigLoader configLoader)
    {
        this.stdout = stdout ?? throw new ArgumentNullException(nameof(stdout));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
        this.serviceBootstrap = serviceBootstrap ?? throw new ArgumentNullException(nameof(serviceBootstrap));
        this.configLoader = configLoader ?? throw new ArgumentNullException(nameof(configLoader));
    }

    public async Task<int> RunStartAsync(CancellationToken cancellationToken)
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

        if (settings.EnableSsh)
        {
            var sshExit = await serviceBootstrap.StartSshdAsync(cancellationToken).ConfigureAwait(false);
            if (sshExit != 0)
            {
                return sshExit;
            }
        }

        var dockerExit = await serviceBootstrap.StartDockerdAsync(cancellationToken).ConfigureAwait(false);
        if (dockerExit != 0)
        {
            await stderr.WriteLineAsync("Warning: DinD not available").ConfigureAwait(false);
        }

        await stdout.WriteLineAsync("[OK] ContainAI devcontainer ready").ConfigureAwait(false);
        return 0;
    }

    public Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken)
        => serviceBootstrap.VerifySysboxAsync(cancellationToken);
}
