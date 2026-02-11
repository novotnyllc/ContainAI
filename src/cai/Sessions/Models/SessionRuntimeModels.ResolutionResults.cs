namespace ContainAI.Cli.Host;

internal sealed record ResolutionResult<T>(bool Success, T? Value, string? Error, int ErrorCode)
{
    public static ResolutionResult<T> SuccessResult(T value) => new(true, value, null, 1);

    public static ResolutionResult<T> ErrorResult(string error, int errorCode = 1) => new(false, default, error, errorCode);
}

internal sealed record ContextSelectionResult(bool Success, string? Context, string? Error, int ErrorCode)
{
    public static ContextSelectionResult FromContext(string context) => new(true, context, null, 1);

    public static ContextSelectionResult FromError(string error, int errorCode = 1) => new(false, null, error, errorCode);
}

internal sealed record FindContainerByNameResult(bool Exists, string? Context, string? Error, int ErrorCode);

internal sealed record ContainerLookupResult(string? ContainerName, string? Error, int ErrorCode)
{
    public static ContainerLookupResult Success(string name) => new(name, null, 1);

    public static ContainerLookupResult Empty() => new(null, null, 1);

    public static ContainerLookupResult FromError(string error, int errorCode = 1) => new(null, error, errorCode);
}
