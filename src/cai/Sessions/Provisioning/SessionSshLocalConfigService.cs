using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Provisioning;

internal sealed class SessionSshLocalConfigService : ISessionSshLocalConfigService
{
    private readonly ISessionSshKeyPairService keyPairService;
    private readonly ISessionSshKnownHostsService knownHostsService;
    private readonly ISessionSshHostConfigService hostConfigService;

    public SessionSshLocalConfigService()
        : this(new SessionSshKeyPairService(), new SessionSshKnownHostsService(), new SessionSshHostConfigService())
    {
    }

    internal SessionSshLocalConfigService(
        ISessionSshKeyPairService sessionSshKeyPairService,
        ISessionSshKnownHostsService sessionSshKnownHostsService,
        ISessionSshHostConfigService sessionSshHostConfigService)
    {
        keyPairService = sessionSshKeyPairService ?? throw new ArgumentNullException(nameof(sessionSshKeyPairService));
        knownHostsService = sessionSshKnownHostsService ?? throw new ArgumentNullException(nameof(sessionSshKnownHostsService));
        hostConfigService = sessionSshHostConfigService ?? throw new ArgumentNullException(nameof(sessionSshHostConfigService));
    }

    public Task<ResolutionResult<bool>> EnsureSshHostConfigAsync(string containerName, string sshPort, CancellationToken cancellationToken)
        => hostConfigService.EnsureSshHostConfigAsync(containerName, sshPort, cancellationToken);

    public Task<ResolutionResult<bool>> UpdateKnownHostsAsync(string containerName, string sshPort, CancellationToken cancellationToken)
        => knownHostsService.UpdateKnownHostsAsync(containerName, sshPort, cancellationToken);

    public Task<ResolutionResult<bool>> EnsureSshKeyPairAsync(CancellationToken cancellationToken)
        => keyPairService.EnsureSshKeyPairAsync(cancellationToken);
}
