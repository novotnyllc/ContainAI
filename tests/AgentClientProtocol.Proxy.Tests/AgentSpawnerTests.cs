using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AgentSpawnerTests
{
    [Fact]
    public async Task SpawnAgent_DirectSpawn_WithMissingBinary_ThrowsWithClearMessage()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(TextWriter.Null);
        var missingAgent = $"containai-missing-{Guid.NewGuid():N}";

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => spawner.SpawnAgentAsync(session, missingAgent, TestContext.Current.CancellationToken));

        Assert.Contains($"Agent '{missingAgent}' not found", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SpawnAgent_DirectSpawn_StartsTransport()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(TextWriter.Null);

        await spawner.SpawnAgentAsync(session, "sh", TestContext.Current.CancellationToken);
        Assert.NotNull(session.AgentOutput);
        Assert.NotNull(session.AgentExecutionTask);
        session.Cancel();
    }

    [Fact]
    public async Task SpawnAgent_DirectSpawn_ForwardsStderrOutput()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        using var temp = new TempDirectory();
        var fakeAgentPath = Path.Combine(temp.Path, "fake-agent");
        await File.WriteAllTextAsync(
            fakeAgentPath,
            "#!/usr/bin/env bash\nprintf 'forwarded-error\\n' >&2\n",
            TestContext.Current.CancellationToken);
        EnsureExecutable(fakeAgentPath);

        using var session = new AcpSession("/tmp/workspace");
        var stderrLineReceived = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var stderr = new MatchNotifyingStringWriter("forwarded-error", stderrLineReceived);
        var spawner = new AgentSpawner(stderr);

        await spawner.SpawnAgentAsync(session, fakeAgentPath, TestContext.Current.CancellationToken);
        await stderrLineReceived.Task.WaitAsync(TimeSpan.FromSeconds(3), TestContext.Current.CancellationToken);
        if (session.AgentExecutionTask != null)
        {
            await session.AgentExecutionTask.WaitAsync(TimeSpan.FromSeconds(3), TestContext.Current.CancellationToken);
        }
        Assert.Contains("forwarded-error", stderr.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SpawnAgent_DirectSpawn_WhenAgentExitsNonZero_ReportsExitCode()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        using var temp = new TempDirectory();
        var fakeAgentPath = Path.Combine(temp.Path, "fake-agent-fail");
        await File.WriteAllTextAsync(
            fakeAgentPath,
            "#!/usr/bin/env bash\nexit 7\n",
            TestContext.Current.CancellationToken);
        EnsureExecutable(fakeAgentPath);

        using var session = new AcpSession("/tmp/workspace");
        using var stderr = new StringWriter();
        var spawner = new AgentSpawner(stderr);
        await spawner.SpawnAgentAsync(session, fakeAgentPath, TestContext.Current.CancellationToken);

        if (session.AgentExecutionTask != null)
        {
            await session.AgentExecutionTask.WaitAsync(TimeSpan.FromSeconds(3), TestContext.Current.CancellationToken);
        }

        Assert.Contains("exited with code 7", stderr.ToString(), StringComparison.Ordinal);
    }

    private sealed class MatchNotifyingStringWriter(string expected, TaskCompletionSource completionSource) : StringWriter
    {
        public override void WriteLine(string? value)
        {
            base.WriteLine(value);

            if (!string.IsNullOrWhiteSpace(value) &&
                value.Contains(expected, StringComparison.Ordinal))
            {
                completionSource.TrySetResult();
            }
        }
    }

    private static void EnsureExecutable(string path)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        File.SetUnixFileMode(
            path,
            UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"agent-spawner-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
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
}
