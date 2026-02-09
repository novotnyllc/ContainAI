using System.ComponentModel;
using System.Text;
using System.Threading.Channels;
using CliWrap;
using CliWrap.Exceptions;

namespace AgentClientProtocol.Proxy.Sessions;

/// <summary>
/// Spawns agent processes for ACP sessions.
/// </summary>
public sealed class AgentSpawner : IAgentSpawner
{
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);
    private const int InputChannelCapacity = 512;
    private const int OutputChannelCapacity = 512;
    private readonly TextWriter stderr;

    /// <summary>
    /// Creates a new agent spawner.
    /// </summary>
    /// <param name="errorWriter">Stream to forward agent stderr to.</param>
    public AgentSpawner(TextWriter errorWriter) => stderr = errorWriter;

    /// <inheritdoc />
    public async Task SpawnAgentAsync(AcpSession session, string agent, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentException.ThrowIfNullOrWhiteSpace(agent);

        var input = Channel.CreateBounded<string>(new BoundedChannelOptions(InputChannelCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
            AllowSynchronousContinuations = false,
        });
        var output = Channel.CreateBounded<string>(new BoundedChannelOptions(OutputChannelCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = false,
        });
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var command = BuildCommand(agent)
            .WithValidation(CommandResultValidation.None)
            .WithStandardInputPipe(PipeSource.Create((stream, token) => PumpInputAsync(input.Reader, stream, token)))
            .WithStandardOutputPipe(PipeTarget.ToDelegate((line, token) => output.Writer.WriteAsync(line, token).AsTask(), Utf8NoBom))
            .WithStandardErrorPipe(PipeTarget.ToDelegate((line, _) => stderr.WriteLineAsync(line), Utf8NoBom));

        var executionTask = RunCommandAsync(command, output.Writer, started, session.CancellationToken);
        session.AttachAgentTransport(input.Writer, output.Reader, executionTask);

        try
        {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is CommandExecutionException or InvalidOperationException or IOException or Win32Exception)
        {
            session.Cancel();
            throw CreateStartFailure(agent, ex);
        }
    }

    private static InvalidOperationException CreateStartFailure(string agent, Exception ex) =>
        new(
            $"Agent '{agent}' not found. Ensure the agent binary is installed and in PATH.",
            ex);

    private static Command BuildCommand(string agent)
        => Cli.Wrap(agent).WithArguments(args => args.Add("--acp"));

    private async Task RunCommandAsync(
        Command command,
        ChannelWriter<string> output,
        TaskCompletionSource started,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await command.ExecuteAsync(
                static _ => { },
                _ => started.TrySetResult(),
                cancellationToken,
                cancellationToken).ConfigureAwait(false);

            started.TrySetResult();
            if (result.ExitCode != 0)
            {
                await stderr.WriteLineAsync($"Agent process exited with code {result.ExitCode}.").ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            started.TrySetCanceled(cancellationToken);
        }
        catch (Exception ex) when (ex is CommandExecutionException or InvalidOperationException or IOException or Win32Exception)
        {
            started.TrySetException(ex);
        }
        finally
        {
            output.TryComplete();
        }
    }

    private static async Task PumpInputAsync(ChannelReader<string> input, Stream output, CancellationToken cancellationToken)
    {
        using var writer = new StreamWriter(output, Utf8NoBom, leaveOpen: true)
        {
            AutoFlush = true,
        };

        await foreach (var line in input.ReadAllAsync(cancellationToken).ConfigureAwait(false))
        {
            await writer.WriteLineAsync(line.AsMemory(), cancellationToken).ConfigureAwait(false);
        }
    }
}
