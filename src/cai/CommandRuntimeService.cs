using System.ComponentModel;
using System.Diagnostics;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class CommandRuntimeService : ICommandRuntimeService
{
    public Task<int> RunProcessAsync(ProcessExecutionSpec spec, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(spec);
        return RunProcessCoreAsync(spec, cancellationToken);
    }

    public Task<int> RunDockerAsync(DockerExecutionSpec spec, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(spec);

        var processSpec = CreateDockerProcessSpec(spec);
        return RunProcessCoreAsync(processSpec, cancellationToken);
    }

    private static ProcessExecutionSpec CreateDockerProcessSpec(DockerExecutionSpec spec)
    {
        if (spec.PreferContainAiDockerExecutable && IsExecutableOnPath("containai-docker"))
        {
            return new ProcessExecutionSpec(
                FileName: "containai-docker",
                Arguments: spec.Arguments.ToArray());
        }

        var args = new List<string>(capacity: spec.Arguments.Count + 2);
        if (!string.IsNullOrWhiteSpace(spec.ContextName))
        {
            args.Add("--context");
            args.Add(spec.ContextName);
        }

        foreach (var argument in spec.Arguments)
        {
            args.Add(argument);
        }

        return new ProcessExecutionSpec(
            FileName: "docker",
            Arguments: args);
    }

    private static async Task<int> RunProcessCoreAsync(ProcessExecutionSpec spec, CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = CreateStartInfo(spec),
        };

        try
        {
            if (!process.Start())
            {
                throw new InvalidOperationException($"Failed to launch process '{spec.FileName}'.");
            }
        }
        catch (Win32Exception ex)
        {
            Console.Error.WriteLine($"Failed to start '{spec.FileName}': {ex.Message}");
            return 127;
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

        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        return process.ExitCode;
    }

    private static ProcessStartInfo CreateStartInfo(ProcessExecutionSpec spec)
    {
        var startInfo = new ProcessStartInfo(spec.FileName)
        {
            UseShellExecute = false,
        };

        foreach (var argument in spec.Arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        if (spec.EnvironmentOverrides is not null)
        {
            foreach (var (key, value) in spec.EnvironmentOverrides)
            {
                if (string.IsNullOrEmpty(value))
                {
                    startInfo.Environment.Remove(key);
                    continue;
                }

                startInfo.Environment[key] = value;
            }
        }

        return startInfo;
    }

    private static bool IsExecutableOnPath(string fileName)
    {
        if (Path.IsPathRooted(fileName) && File.Exists(fileName))
        {
            return true;
        }

        var pathVariable = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathVariable))
        {
            return false;
        }

        var extensions = GetCandidateExtensions();
        foreach (var directory in pathVariable.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(directory, $"{fileName}{extension}");
                if (File.Exists(candidate))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static IReadOnlyList<string> GetCandidateExtensions()
    {
        if (!OperatingSystem.IsWindows())
        {
            return [string.Empty];
        }

        var pathExt = Environment.GetEnvironmentVariable("PATHEXT");
        if (string.IsNullOrWhiteSpace(pathExt))
        {
            return [".exe", ".cmd", ".bat"];
        }

        var parts = pathExt
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        return parts.Length == 0 ? [".exe", ".cmd", ".bat"] : parts;
    }
}
