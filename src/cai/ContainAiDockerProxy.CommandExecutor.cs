namespace ContainAI.Cli.Host;

internal sealed class DockerProxyCommandExecutor : IDockerProxyCommandExecutor
{
    private readonly IDockerProxyProcessRunner processRunner;

    public DockerProxyCommandExecutor(IDockerProxyProcessRunner processRunner) => this.processRunner = processRunner;

    public async Task<int> RunInteractiveAsync(IReadOnlyList<string> args, TextWriter stderr, CancellationToken cancellationToken)
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

    public async Task<DockerProxyProcessResult> RunCaptureAsync(IReadOnlyList<string> args, CancellationToken cancellationToken)
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
