using System.Threading.Channels;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpSessionAdvancedTests
{
    [Fact]
    public async Task WriteToAgentAsync_WhenAgentTransportMissing_DoesNotThrow()
    {
        using var session = new AcpSession("/workspace");

        await session.WriteToAgentAsync(new JsonRpcEnvelope
        {
            Method = "session/prompt",
        }).ConfigureAwait(true);
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenCompletedByTryCompleteResponse_ReturnsResponse()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcEnvelope
        {
            Id = "req-1",
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-1", TimeSpan.FromSeconds(3));
        await Task.Yield();
        var completed = session.TryCompleteResponse(
            "req-1",
            new JsonRpcEnvelope
            {
                Id = "req-1",
                Result = new JsonObject { ["ok"] = true },
            });

        Assert.True(completed);
        var response = await waitTask.ConfigureAwait(true);
        Assert.NotNull(response);
        Assert.Equal("req-1", response.Id?.GetValue<string>());
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenTimeoutExpires_ReturnsNull()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcEnvelope
        {
            Id = "req-timeout",
            Method = "initialize",
        };

        var response = await session
            .SendAndWaitForResponseAsync(request, "req-timeout", TimeSpan.FromMilliseconds(50))
            .ConfigureAwait(true);

        Assert.Null(response);
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenSessionCanceled_ReturnsNull()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcEnvelope
        {
            Id = "req-cancel",
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-cancel", TimeSpan.FromSeconds(10));
        session.Cancel();

        var response = await waitTask.ConfigureAwait(true);
        Assert.Null(response);
    }

    [Fact]
    public async Task WriteToAgentAsync_WritesJsonLineToTransportInput()
    {
        var input = Channel.CreateUnbounded<string>();
        var output = Channel.CreateUnbounded<string>();
        using var session = new AcpSession("/workspace");
        session.AttachAgentTransport(input.Writer, output.Reader, Task.CompletedTask);

        await session.WriteToAgentAsync(new JsonRpcEnvelope
        {
            Id = "capture",
            Method = "session/prompt",
            Params = new JsonObject { ["sessionId"] = "proxy-1" },
        }).ConfigureAwait(true);

        var line = await input.Reader.ReadAsync(TestContext.Current.CancellationToken).ConfigureAwait(true);
        Assert.Contains("\"method\":\"session/prompt\"", line, StringComparison.Ordinal);
        Assert.Contains("\"sessionId\":\"proxy-1\"", line, StringComparison.Ordinal);
    }

    [Fact]
    public async Task WriteToAgentAsync_WhenTransportInputChannelClosed_DoesNotThrow()
    {
        var input = Channel.CreateUnbounded<string>();
        var output = Channel.CreateUnbounded<string>();
        using var session = new AcpSession("/workspace");
        session.AttachAgentTransport(input.Writer, output.Reader, Task.CompletedTask);
        input.Writer.TryComplete();

        await session.WriteToAgentAsync(new JsonRpcEnvelope
        {
            Method = "session/prompt",
            Params = new JsonObject
            {
                ["sessionId"] = "proxy-closed",
            },
        }).ConfigureAwait(true);
    }

    [Fact]
    public async Task SendAndWaitForResponseAsync_WhenAgentTaskCompletesEarly_ReturnsNull()
    {
        var input = Channel.CreateUnbounded<string>();
        var output = Channel.CreateUnbounded<string>();
        using var session = new AcpSession("/workspace");
        session.AttachAgentTransport(input.Writer, output.Reader, Task.CompletedTask);

        var request = new JsonRpcEnvelope
        {
            Id = "req-finished",
            Method = "initialize",
        };

        var response = await session
            .SendAndWaitForResponseAsync(request, "req-finished", TimeSpan.FromSeconds(5))
            .ConfigureAwait(true);

        Assert.Null(response);
    }

    [Fact]
    public async Task Dispose_WithPendingRequest_CancelsPendingWaiter()
    {
        using var session = new AcpSession("/workspace");
        var request = new JsonRpcEnvelope
        {
            Id = "req-dispose",
            Method = "initialize",
        };

        var waitTask = session.SendAndWaitForResponseAsync(request, "req-dispose", TimeSpan.FromSeconds(30));
        session.Dispose();

        var response = await waitTask.ConfigureAwait(true);
        Assert.Null(response);
    }
}
