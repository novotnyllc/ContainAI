using System.Diagnostics;

namespace ContainAI.Cli.Tests;

internal static class ShellTestSupport
{
    public static string RepositoryRoot { get; } = ResolveRepositoryRoot();

    public static TemporaryDirectory CreateTemporaryDirectory(string prefix)
    {
        var path = Path.Combine(Path.GetTempPath(), $"{prefix}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return new TemporaryDirectory(path);
    }

    public static string ShellQuote(string value) => $"'{value.Replace("'", "'\"'\"'")}'";

    public static async Task<ProcessResult> RunBashAsync(
        string script,
        string? workingDirectory = null,
        IReadOnlyDictionary<string, string?>? environment = null,
        CancellationToken cancellationToken = default)
    {
        var startInfo = new ProcessStartInfo("bash")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = workingDirectory ?? RepositoryRoot,
        };

        startInfo.ArgumentList.Add("-lc");
        startInfo.ArgumentList.Add($"set -euo pipefail\n{script}");

        if (environment is not null)
        {
            foreach (var item in environment)
            {
                startInfo.Environment[item.Key] = item.Value;
            }
        }

        using var process = new Process
        {
            StartInfo = startInfo,
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("Failed to start bash process.");
        }

        using var cancellationRegistration = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // Ignore cleanup failures during cancellation.
            }
        });

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();

        await process.WaitForExitAsync(cancellationToken);

        return new ProcessResult(
            process.ExitCode,
            await stdoutTask,
            await stderrTask);
    }

    private static string ResolveRepositoryRoot()
    {
        foreach (var candidate in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
        {
            var current = Path.GetFullPath(candidate);
            while (!string.IsNullOrWhiteSpace(current))
            {
                if (File.Exists(Path.Combine(current, "ContainAI.slnx")))
                {
                    return current;
                }

                var parent = Directory.GetParent(current);
                if (parent is null)
                {
                    break;
                }

                current = parent.FullName;
            }
        }

        throw new DirectoryNotFoundException("Could not resolve repository root containing ContainAI.slnx.");
    }

    internal sealed record ProcessResult(int ExitCode, string StdOut, string StdErr);
}

internal sealed class TemporaryDirectory : IDisposable
{
    public TemporaryDirectory(string path)
    {
        Path = path;
    }

    public string Path { get; }

    public void Dispose()
    {
        if (Directory.Exists(Path))
        {
            Directory.Delete(Path, recursive: true);
        }
    }
}
