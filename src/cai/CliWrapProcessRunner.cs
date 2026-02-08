using System.Text;
using CliWrap;
using CliWrap.Buffered;

namespace ContainAI.Cli.Host;

internal static class CliWrapProcessRunner
{
    public static async Task<CliWrapProcessResult> RunCaptureAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        string? workingDirectory = null,
        string? standardInput = null,
        IReadOnlyDictionary<string, string?>? environment = null)
    {
        var command = global::CliWrap.Cli.Wrap(executable)
            .WithValidation(CommandResultValidation.None);

        command = command.WithArguments(arguments);

        if (!string.IsNullOrWhiteSpace(workingDirectory))
        {
            command = command.WithWorkingDirectory(workingDirectory);
        }

        if (environment is not null)
        {
            command = command.WithEnvironmentVariables(environment);
        }

        if (standardInput is not null)
        {
            command = command.WithStandardInputPipe(PipeSource.FromString(standardInput, Encoding.UTF8));
        }

        var buffered = await command.ExecuteBufferedAsync(Encoding.UTF8, cancellationToken).ConfigureAwait(false);
        return new CliWrapProcessResult(buffered.ExitCode, buffered.StandardOutput, buffered.StandardError);
    }

    public static async Task<int> RunInteractiveAsync(
        string executable,
        IReadOnlyList<string> arguments,
        CancellationToken cancellationToken,
        IReadOnlyDictionary<string, string?>? environment = null)
    {
        using var standardInput = Console.OpenStandardInput();
        using var standardOutput = Console.OpenStandardOutput();
        using var standardError = Console.OpenStandardError();

        var command = global::CliWrap.Cli.Wrap(executable)
            .WithValidation(CommandResultValidation.None)
            .WithArguments(arguments)
            .WithStandardInputPipe(PipeSource.FromStream(standardInput))
            .WithStandardOutputPipe(PipeTarget.ToStream(standardOutput))
            .WithStandardErrorPipe(PipeTarget.ToStream(standardError));

        if (environment is not null)
        {
            command = command.WithEnvironmentVariables(environment);
        }

        var result = await command.ExecuteAsync(cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }
}

internal readonly record struct CliWrapProcessResult(int ExitCode, string StandardOutput, string StandardError);
