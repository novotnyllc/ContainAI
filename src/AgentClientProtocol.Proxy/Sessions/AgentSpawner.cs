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
    private readonly bool _directSpawn;
    private readonly TextWriter _stderr;
    private readonly string _caiExecutable;

    /// <summary>
    /// Creates a new agent spawner.
    /// </summary>
    /// <param name="directSpawn">If true, spawns the agent directly; otherwise wraps with cai exec.</param>
    /// <param name="stderr">Stream to forward agent stderr to.</param>
    /// <param name="caiExecutable">ContainAI executable path used for container-side execution.</param>
    public AgentSpawner(bool directSpawn, TextWriter stderr, string caiExecutable = "cai")
    {
        _directSpawn = directSpawn;
        _stderr = stderr;
        _caiExecutable = caiExecutable;
    }

    /// <inheritdoc />
    public async Task SpawnAgentAsync(AcpSession session, string agent, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(session);
        ArgumentException.ThrowIfNullOrWhiteSpace(agent);

        var input = Channel.CreateUnbounded<string>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = false,
            AllowSynchronousContinuations = false,
        });
        var output = Channel.CreateUnbounded<string>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true,
            AllowSynchronousContinuations = false,
        });
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var command = BuildCommand(session, agent)
            .WithValidation(CommandResultValidation.None)
            .WithStandardInputPipe(PipeSource.Create((stream, token) => PumpInputAsync(input.Reader, stream, token)))
            .WithStandardOutputPipe(PipeTarget.ToDelegate((line, token) => output.Writer.WriteAsync(line, token).AsTask(), Utf8NoBom))
            .WithStandardErrorPipe(PipeTarget.ToDelegate((line, _) => _stderr.WriteLineAsync(line), Utf8NoBom));

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

    private Command BuildCommand(AcpSession session, string agent)
    {
        if (_directSpawn)
        {
            return Cli.Wrap(agent)
                .WithArguments(args => args.Add("--acp"));
        }

        return Cli.Wrap(_caiExecutable)
            .WithEnvironmentVariables(env => env.Set("CAI_NO_UPDATE_CHECK", "1"))
            .WithArguments(args => args
                .Add("exec")
                .Add("--workspace")
                .Add(session.Workspace)
                .Add("--quiet")
                .Add("--")
                .Add("bash")
                // Use -c (not -lc) to avoid login shell profile output on stdout.
                .Add("-c")
                // Safe: agent name passed as $1, not string-interpolated into shell body.
                .Add("command -v -- \"$1\" >/dev/null 2>&1 || { printf \"Agent '%s' not found in container\\n\" \"$1\" >&2; exit 127; }; exec -- \"$1\" --acp")
                .Add("--")
                .Add(agent));
    }

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
                await _stderr.WriteLineAsync($"Agent process exited with code {result.ExitCode}.").ConfigureAwait(false);
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
