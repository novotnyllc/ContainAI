using ContainAI.Cli.Host.RuntimeSupport.Models;

namespace ContainAI.Cli.Host.RuntimeSupport.Process;

internal static class CaiRuntimeProcessHelpers
{
    internal static async Task<RuntimeProcessResult> RunProcessCaptureAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? standardInput = null)
    {
        try
        {
            var result = await CliWrapProcessRunner
                .RunCaptureAsync(fileName, arguments, cancellationToken, standardInput: standardInput)
                .ConfigureAwait(false);

            return new RuntimeProcessResult(result.ExitCode, result.StandardOutput, result.StandardError);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new RuntimeProcessResult(1, string.Empty, ex.Message);
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new RuntimeProcessResult(1, string.Empty, ex.Message);
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            return new RuntimeProcessResult(1, string.Empty, ex.Message);
        }
    }

    internal static async Task<int> RunProcessInteractiveAsync(
        string fileName,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken)
    {
        try
        {
            return await CliWrapProcessRunner.RunInteractiveAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{fileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
    }

    internal static async Task<bool> CommandSucceedsAsync(string fileName, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await RunProcessCaptureAsync(fileName, arguments, cancellationToken).ConfigureAwait(false);
        return result.ExitCode == 0;
    }

    internal static async Task CopyDirectoryAsync(string sourceDirectory, string destinationDirectory, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(destinationDirectory);

        foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationFile = Path.Combine(destinationDirectory, Path.GetFileName(sourceFile));
            using var sourceStream = File.OpenRead(sourceFile);
            using var destinationStream = File.Create(destinationFile);
            await sourceStream.CopyToAsync(destinationStream, cancellationToken).ConfigureAwait(false);
        }

        foreach (var sourceSubdirectory in Directory.EnumerateDirectories(sourceDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destinationSubdirectory = Path.Combine(destinationDirectory, Path.GetFileName(sourceSubdirectory));
            await CopyDirectoryAsync(sourceSubdirectory, destinationSubdirectory, cancellationToken).ConfigureAwait(false);
        }
    }

    internal static string EscapeJson(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal)
            .Replace("\t", "\\t", StringComparison.Ordinal);
    }
}
