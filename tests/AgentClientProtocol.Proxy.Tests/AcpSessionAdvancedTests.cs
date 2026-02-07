using System.Diagnostics;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpSessionAdvancedTests
{
    [Fact]
    public async Task WriteToAgentAsync_WhenAgentProcessMissing_DoesNotThrow()
    {
        using var session = new AcpSession("/workspace");

        await session.WriteToAgentAsync(new JsonRpcMessage
        {
            Method = "session/prompt",
        });
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenCompletedByTryCompleteResponse_ReturnsResponse()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcMessage
        {
            Id = JsonValue.Create("req-1"),
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-1", TimeSpan.FromSeconds(3));
        await Task.Yield();
        var completed = session.TryCompleteResponse(
            "req-1",
            new JsonRpcMessage
            {
                Id = JsonValue.Create("req-1"),
                Result = new JsonObject { ["ok"] = true },
            });

        Assert.True(completed);
        var response = await waitTask;
        Assert.NotNull(response);
        Assert.Equal("req-1", response.Id?.GetValue<string>());
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenTimeoutExpires_ReturnsNull()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcMessage
        {
            Id = JsonValue.Create("req-timeout"),
            Method = "initialize",
        };

        var response = await session.SendAndWaitForResponseAsync(request, "req-timeout", TimeSpan.FromMilliseconds(50));

        Assert.Null(response);
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenSessionCanceled_ReturnsNull()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcMessage
        {
            Id = JsonValue.Create("req-cancel"),
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-cancel", TimeSpan.FromSeconds(10));
        session.Cancel();

        var response = await waitTask;
        Assert.Null(response);
    }

    [Fact]
    public async Task WriteToAgentAsync_WritesJsonLineToAgentStdin()
    {
        using var temp = new TempFile();
        var psi = new ProcessStartInfo("bash")
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        psi.ArgumentList.Add("-c");
        psi.ArgumentList.Add($"cat > '{temp.Path}'");

        using var process = Process.Start(psi);
        Assert.NotNull(process);

        using var session = new AcpSession("/workspace")
        {
            AgentProcess = process,
        };

        await session.WriteToAgentAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("capture"),
            Method = "session/prompt",
            Params = new JsonObject { ["sessionId"] = "proxy-1" },
        });

        process.StandardInput.Close();
        await process.WaitForExitAsync(TestContext.Current.CancellationToken);

        var lines = await File.ReadAllLinesAsync(temp.Path, TestContext.Current.CancellationToken);
        Assert.Single(lines);
        Assert.Contains("\"method\":\"session/prompt\"", lines[0], StringComparison.Ordinal);
        Assert.Contains("\"sessionId\":\"proxy-1\"", lines[0], StringComparison.Ordinal);
    }

    [Fact]
    public async Task Dispose_WithPendingRequest_CancelsPendingWaiter()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcMessage
        {
            Id = JsonValue.Create("req-dispose"),
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-dispose", TimeSpan.FromSeconds(30));
        session.Dispose();

        var response = await waitTask;
        Assert.Null(response);
    }

    [Fact]
    public void Dispose_WithNonStartedProcess_IgnoresKillErrors()
    {
        var session = new AcpSession("/workspace")
        {
            AgentProcess = new Process(),
        };

        var exception = Record.Exception(session.Dispose);

        Assert.Null(exception);
    }

    private sealed class TempFile : IDisposable
    {
        public TempFile() => Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"acp-session-{Guid.NewGuid():N}.log");

        public string Path { get; }

        public void Dispose()
        {
            if (File.Exists(Path))
            {
                File.Delete(Path);
            }
        }
    }
}
