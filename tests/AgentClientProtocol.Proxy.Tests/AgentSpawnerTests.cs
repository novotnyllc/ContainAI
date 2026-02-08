using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AgentSpawnerTests
{
    [Fact]
    public async Task SpawnAgent_DirectSpawn_WithMissingBinary_ThrowsWithClearMessage()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: true, TextWriter.Null);
        var missingAgent = $"containai-missing-{Guid.NewGuid():N}";

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => spawner.SpawnAgentAsync(session, missingAgent, TestContext.Current.CancellationToken));

        Assert.Contains($"Agent '{missingAgent}' not found", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SpawnAgent_DirectSpawn_StartsTransport()
    {
        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: true, TextWriter.Null);

        await spawner.SpawnAgentAsync(session, "sh", TestContext.Current.CancellationToken);
        Assert.NotNull(session.AgentOutput);
        Assert.NotNull(session.AgentExecutionTask);
        session.Cancel();
    }

    [Fact]
    public async Task SpawnAgent_ContainerMode_UsesCaiExecWrapperArguments()
    {
        using var temp = new TempDirectory();
        var fakeCaiPath = Path.Combine(temp.Path, "cai");
        var argsFile = Path.Combine(temp.Path, "args.log");
        var envFile = Path.Combine(temp.Path, "env.log");

        var script = $$"""
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$CAI_NO_UPDATE_CHECK" > "{{envFile}}"
printf '%s\n' "$@" > "{{argsFile}}"
while IFS= read -r _; do
  :
done
""";
        await File.WriteAllTextAsync(fakeCaiPath, script.ReplaceLineEndings("\n"), TestContext.Current.CancellationToken);
        EnsureExecutable(fakeCaiPath);

        using var session = new AcpSession("/tmp/workspace");
        var spawner = new AgentSpawner(directSpawn: false, TextWriter.Null, fakeCaiPath);
        await spawner.SpawnAgentAsync(session, "claude", TestContext.Current.CancellationToken);
        await session.WriteToAgentAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("probe"),
            Method = "session/prompt",
            Params = new JsonObject
            {
                ["sessionId"] = "proxy-1",
            },
        }).ConfigureAwait(true);

        await WaitForFileAsync(argsFile, TestContext.Current.CancellationToken);
        session.Cancel();
        if (session.AgentExecutionTask != null)
        {
            await session.AgentExecutionTask.WaitAsync(TimeSpan.FromSeconds(2), TestContext.Current.CancellationToken);
        }

        var args = await File.ReadAllLinesAsync(argsFile, TestContext.Current.CancellationToken);
        Assert.Equal("exec", args[0]);
        Assert.Equal("--workspace", args[1]);
        Assert.Equal("/tmp/workspace", args[2]);
        Assert.Equal("--quiet", args[3]);
        Assert.Equal("--", args[4]);
        Assert.Equal("bash", args[5]);
        Assert.Equal("-c", args[6]);
        Assert.Contains("command -v -- \"$1\"", args[7], StringComparison.Ordinal);
        Assert.Equal("--", args[8]);
        Assert.Equal("claude", args[9]);

        var env = await File.ReadAllTextAsync(envFile, TestContext.Current.CancellationToken);
        Assert.Contains("1", env, StringComparison.Ordinal);
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
        var spawner = new AgentSpawner(directSpawn: true, stderr);

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
        var spawner = new AgentSpawner(directSpawn: true, stderr);
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

    private static async Task WaitForFileAsync(string path, CancellationToken cancellationToken)
    {
        if (File.Exists(path))
        {
            return;
        }

        var directory = Path.GetDirectoryName(path);
        var fileName = Path.GetFileName(path);
        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new InvalidOperationException($"Unable to watch directory for path: {path}");
        }

        var fileCreated = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var watcher = new FileSystemWatcher(directory, fileName)
        {
            EnableRaisingEvents = true,
        };
        using var cancellation = cancellationToken.Register(
            static state => ((TaskCompletionSource)state!).TrySetCanceled(),
            fileCreated);

        watcher.Created += (_, _) => fileCreated.TrySetResult();
        watcher.Changed += (_, _) =>
        {
            if (File.Exists(path))
            {
                fileCreated.TrySetResult();
            }
        };

        if (File.Exists(path))
        {
            return;
        }

        await fileCreated.Task.WaitAsync(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false);
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
