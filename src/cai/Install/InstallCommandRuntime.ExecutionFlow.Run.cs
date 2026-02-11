using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class InstallCommandExecution
{
    public async Task<int> RunAsync(InstallCommandOptions options, CancellationToken cancellationToken)
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
            return 1;
        }

        try
        {
            return await ExecuteInstallFlowAsync(
                options,
                sourceExecutablePath,
                installDir,
                binDir,
                homeDirectory,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (IOException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (UnauthorizedAccessException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (ArgumentException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (NotSupportedException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex)
        {
            return await WriteErrorAndReturnAsync(ex.Message, cancellationToken).ConfigureAwait(false);
        }
    }
}
