namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private static EnsuredSession EnsureError<T>(ResolutionResult<T> result) =>
        EnsuredSession.ErrorResult(result.Error!, result.ErrorCode);

    private static ResolutionResult<TTarget> ErrorFrom<TSource, TTarget>(ResolutionResult<TSource> result) =>
        ResolutionResult<TTarget>.ErrorResult(result.Error!, result.ErrorCode);

    private static ResolutionResult<T> ErrorResult<T>(string error, int errorCode = 1) =>
        ResolutionResult<T>.ErrorResult(error, errorCode);
}
