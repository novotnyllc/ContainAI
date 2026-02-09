using CliWrap;

namespace ContainAI.Cli.Host;

internal static partial class AgentShimDispatcher
{
    private static async Task<int> ExecuteCommandAsync(string binaryPath, IReadOnlyList<string> commandArgs, CancellationToken cancellationToken)
    {
        using var standardInput = Console.OpenStandardInput();
        using var standardOutput = Console.OpenStandardOutput();
        using var standardError = Console.OpenStandardError();

        var command = global::CliWrap.Cli.Wrap(binaryPath)
            .WithArguments(commandArgs)
            .WithStandardInputPipe(PipeSource.FromStream(standardInput))
            .WithStandardOutputPipe(PipeTarget.ToStream(standardOutput))
            .WithStandardErrorPipe(PipeTarget.ToStream(standardError))
            .WithValidation(CommandResultValidation.None);

        var result = await command.ExecuteAsync(cancellationToken).ConfigureAwait(false);
        return result.ExitCode;
    }
}
