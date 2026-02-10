namespace ContainAI.Cli.Host;

internal interface ISessionSshBootstrapService
{
    Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken);
}

internal sealed partial class SessionSshBootstrapService : ISessionSshBootstrapService
{
    private readonly ISessionSshLocalConfigService localConfigService;
    private readonly ISessionSshPortReadinessService portReadinessService;

    public SessionSshBootstrapService()
        : this(new SessionSshLocalConfigService(), new SessionSshPortReadinessService())
    {
    }

    internal SessionSshBootstrapService(
        ISessionSshLocalConfigService sessionSshLocalConfigService,
        ISessionSshPortReadinessService sessionSshPortReadinessService)
    {
        localConfigService = sessionSshLocalConfigService ?? throw new ArgumentNullException(nameof(sessionSshLocalConfigService));
        portReadinessService = sessionSshPortReadinessService ?? throw new ArgumentNullException(nameof(sessionSshPortReadinessService));
    }

}
