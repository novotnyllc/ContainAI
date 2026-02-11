namespace ContainAI.Cli.Host;

internal interface ISessionSshBootstrapService
{
    Task<ResolutionResult<bool>> EnsureSshBootstrapAsync(
        ResolvedTarget resolved,
        string sshPort,
        CancellationToken cancellationToken);
}
