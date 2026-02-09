namespace ContainAI.Cli.Host;

internal sealed partial class SessionContainerProvisioner
{
    private static async Task<ResolutionResult<ExistingContainerAttachment>> FindAttachableContainerAsync(
        SessionCommandOptions options,
        ResolvedTarget resolved,
        CancellationToken cancellationToken)
    {
        var labelState = await SessionTargetResolver.ReadContainerLabelsAsync(
            resolved.ContainerName,
            resolved.Context,
            cancellationToken).ConfigureAwait(false);
        var exists = labelState.Exists;

        if (exists && !labelState.IsOwned)
        {
            var code = options.Mode == SessionMode.Run ? 1 : 15;
            return ErrorResult<ExistingContainerAttachment>(
                $"Container '{resolved.ContainerName}' exists but was not created by ContainAI",
                code);
        }

        if (options.Fresh && exists)
        {
            await RemoveContainerAsync(resolved.Context, resolved.ContainerName, cancellationToken).ConfigureAwait(false);
            exists = false;
        }

        if (exists &&
            !string.IsNullOrWhiteSpace(options.DataVolume) &&
            !string.Equals(labelState.DataVolume, resolved.DataVolume, StringComparison.Ordinal))
        {
            return ErrorResult<ExistingContainerAttachment>(
                $"Container '{resolved.ContainerName}' already uses volume '{labelState.DataVolume}'. Use --fresh to recreate with a different volume.");
        }

        if (!exists)
        {
            return ResolutionResult<ExistingContainerAttachment>.SuccessResult(ExistingContainerAttachment.NotFound);
        }

        return ResolutionResult<ExistingContainerAttachment>.SuccessResult(
            new ExistingContainerAttachment(
                Exists: true,
                State: labelState.State,
                SshPort: labelState.SshPort));
    }

    private sealed record ExistingContainerAttachment(
        bool Exists,
        string? State,
        string? SshPort)
    {
        internal static readonly ExistingContainerAttachment NotFound = new(
            Exists: false,
            State: null,
            SshPort: null);
    }
}
