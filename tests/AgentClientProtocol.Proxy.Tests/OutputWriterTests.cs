using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class OutputWriterTests
{
    [Fact]
    public async Task RunAsync_WritesNdjsonMessagesInOrder()
    {
        using var stdout = new MemoryStream();
        var writer = new OutputWriter(stdout);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);

        var runTask = writer.RunAsync(cts.Token);

        await writer.EnqueueAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("1"),
            Method = "initialize",
        });
        await writer.EnqueueAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("2"),
            Result = new JsonObject { ["ok"] = true },
        });

        writer.Complete();
        await runTask.WaitAsync(TestContext.Current.CancellationToken);

        var payload = Encoding.UTF8.GetString(stdout.ToArray());
        var lines = payload
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        Assert.Equal(2, lines.Length);
        using var first = JsonDocument.Parse(lines[0]);
        using var second = JsonDocument.Parse(lines[1]);
        Assert.Equal("1", first.RootElement.GetProperty("id").GetString());
        Assert.Equal("2", second.RootElement.GetProperty("id").GetString());
        Assert.True(second.RootElement.GetProperty("result").GetProperty("ok").GetBoolean());
    }

    [Fact]
    public async Task RunAsync_Cancellation_StopsWithoutThrowing()
    {
        using var stdout = new MemoryStream();
        var writer = new OutputWriter(stdout);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(TestContext.Current.CancellationToken);

        var runTask = writer.RunAsync(cts.Token);
        await cts.CancelAsync();
        await runTask.WaitAsync(TestContext.Current.CancellationToken);
    }
}
