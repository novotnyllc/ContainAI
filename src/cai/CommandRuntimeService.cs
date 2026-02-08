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
        try
        {
            var result = await CliWrapProcessRunner.RunInteractiveAsync(
                spec.FileName,
                spec.Arguments,
                cancellationToken,
                spec.EnvironmentOverrides).ConfigureAwait(false);
            return result;
        }
        catch (InvalidOperationException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{spec.FileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (IOException ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{spec.FileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
        catch (System.ComponentModel.Win32Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            await Console.Error.WriteLineAsync($"Failed to start '{spec.FileName}': {ex.Message}").ConfigureAwait(false);
            return 127;
        }
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

    private static string[] GetCandidateExtensions()
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
