namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private static EnsuredSession EnsureError<T>(ResolutionResult<T> result) =>
        EnsuredSession.ErrorResult(result.Error!, result.ErrorCode);
}
