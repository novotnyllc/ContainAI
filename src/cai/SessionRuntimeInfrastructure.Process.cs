namespace ContainAI.Cli.Host;

internal static partial class SessionRuntimeInfrastructure
{
    public static Task<ProcessResult> RunTomlAsync(Func<TomlCommandResult> operation, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var result = operation();
        return Task.FromResult(new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError));
    }

    public static async Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        TextWriter errorWriter,
        CancellationToken cancellationToken)
    {
        try
        {
            return await CliWrapProcessRunner.RunInteractiveAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await errorWriter.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    public static async Task<ProcessResult> RunProcessCaptureAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        try
        {
            var result = await CliWrapProcessRunner.RunCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
            return new ProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new ProcessResult(127, string.Empty, ex.Message);
        }
    }
}
