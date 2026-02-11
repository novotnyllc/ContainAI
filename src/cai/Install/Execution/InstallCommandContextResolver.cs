using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal interface IInstallCommandContextResolver
{
    Task<InstallCommandContextResolutionResult> ResolveAsync(InstallCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class InstallCommandContextResolver : IInstallCommandContextResolver
{
    private readonly IInstallPathResolver pathResolver;
    private readonly IInstallCommandOutput output;

    public InstallCommandContextResolver(IInstallPathResolver installPathResolver, IInstallCommandOutput installCommandOutput)
    {
        pathResolver = installPathResolver ?? throw new ArgumentNullException(nameof(installPathResolver));
        output = installCommandOutput ?? throw new ArgumentNullException(nameof(installCommandOutput));
    }

    public async Task<InstallCommandContextResolutionResult> ResolveAsync(InstallCommandOptions options, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(options);

        var installDir = pathResolver.ResolveInstallDirectory(options.InstallDir);
        var binDir = pathResolver.ResolveBinDirectory(options.BinDir);
        var homeDirectory = pathResolver.ResolveHomeDirectory();

        await output.WriteInfoAsync("ContainAI installer starting", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync($"Install directory: {installDir}", cancellationToken).ConfigureAwait(false);
        await output.WriteInfoAsync($"Binary directory: {binDir}", cancellationToken).ConfigureAwait(false);

        if (!string.IsNullOrWhiteSpace(options.Channel))
        {
            await output.WriteInfoAsync($"Channel: {options.Channel}", cancellationToken).ConfigureAwait(false);
        }

        var sourceExecutablePath = pathResolver.ResolveCurrentExecutablePath();
        if (sourceExecutablePath is null)
        {
            await output.WriteErrorAsync("Unable to resolve the current cai executable path.", cancellationToken).ConfigureAwait(false);
            return InstallCommandContextResolutionResult.FailureResult();
        }

        return InstallCommandContextResolutionResult.SuccessResult(
            new InstallCommandContext(options, sourceExecutablePath, installDir, binDir, homeDirectory));
    }
}

internal readonly record struct InstallCommandContextResolutionResult(bool Success, InstallCommandContext? Context)
{
    public static InstallCommandContextResolutionResult SuccessResult(InstallCommandContext context)
        => new(true, context);

    public static InstallCommandContextResolutionResult FailureResult()
        => new(false, null);
}
