namespace ContainAI.Cli.Host;

internal sealed partial class ContainAiDockerProxyService
{
    private async Task<int> RunDockerInteractiveAsync(IReadOnlyList<string> args, TextWriter stderr, CancellationToken cancellationToken)
    {
        try
        {
            return await processRunner.RunInteractiveAsync(args, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await stderr.WriteLineAsync($"Failed to start 'docker': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    private async Task<DockerProxyProcessResult> RunDockerCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        try
        {
            return await processRunner.RunCaptureAsync(args, cancellationToken).ConfigureAwait(false);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
        catch (NotSupportedException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new DockerProxyProcessResult(127, string.Empty, ex.Message);
        }
    }
}
