using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpProxyTests
{
    [Fact]
    public async Task RunAsync_UnknownMethodRequest_ReturnsMethodNotFound()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("req-1"),
                    Method = "unknown/method",
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(stderr);
        var response = Assert.Single(responses);
        Assert.Equal(-32601, response.Error?.Code);
    }

    [Fact]
    public async Task RunAsync_UnknownMethodNotification_DoesNotRespond()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Method = "unknown/notification",
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(stderr);
        Assert.Empty(responses);
    }

    [Fact]
    public async Task RunAsync_Initialize_ReturnsCapabilities()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("init-1"),
                    Method = "initialize",
                    Params = new JsonObject
                    {
                        ["protocolVersion"] = "2025-01-01",
                    },
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(stderr);
        var response = Assert.Single(responses);
        var result = Assert.IsType<JsonObject>(response.Result);
        Assert.Equal("2025-01-01", result["protocolVersion"]?.GetValue<string>());
        Assert.Equal("containai-acp-proxy", result["serverInfo"]?["name"]?.GetValue<string>());
        Assert.Equal(true, result["capabilities"]?["multiSession"]?.GetValue<bool>());
    }

    [Fact]
    public async Task RunAsync_InitializeNotification_DoesNotRespond()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Method = "initialize",
                    Params = new JsonObject
                    {
                        ["protocolVersion"] = "2025-01-01",
                    },
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(stderr);
        Assert.Empty(responses);
    }

    [Fact]
    public async Task RunAsync_SessionPromptForUnknownSession_ReturnsSessionNotFound()
    {
        var (exitCode, responses, _) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("req-2"),
                    Method = "session/prompt",
                    Params = new JsonObject
                    {
                        ["sessionId"] = "missing-session",
                    },
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        var response = Assert.Single(responses);
        Assert.Equal(-32001, response.Error?.Code);
    }

    [Fact]
    public async Task RunAsync_InvalidJson_ReportsParseErrorToStderr()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                "{ invalid-json",
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(responses);
        Assert.Contains("JSON parse error", stderr, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_SessionNewSpawnFailure_ReturnsSessionCreationFailed()
    {
        var (exitCode, responses, _) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("init-2"),
                    Method = "initialize",
                    Params = new JsonObject
                    {
                        ["protocolVersion"] = "2025-01-01",
                    },
                }),
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("session-new-1"),
                    Method = "session/new",
                    Params = new JsonObject
                    {
                        ["cwd"] = Environment.CurrentDirectory,
                    },
                }),
            ],
            new ThrowingSpawner("spawn failed"));

        Assert.Equal(0, exitCode);
        Assert.Equal(2, responses.Count);
        Assert.Equal("init-2", responses[0].Id?.GetValue<string>());
        Assert.Equal(-32000, responses[1].Error?.Code);
        Assert.Contains("Failed to create session", responses[1].Error?.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_RouteThrowsNonJsonException_ReportsProcessingError()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("req-throw"),
                    Method = "session/prompt",
                    Params = new JsonObject
                    {
                        ["sessionId"] = JsonValue.Create(42),
                    },
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(responses);
        Assert.Contains("Error processing message", stderr, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_NullMessageLine_IsIgnored()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                "null",
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(responses);
        Assert.Empty(stderr);
    }

    [Fact]
    public async Task RunAsync_EditorResponseMessage_IsIgnored()
    {
        var (exitCode, responses, stderr) = await RunProxyAsync(
            [
                ToLine(new JsonRpcMessage
                {
                    Id = JsonValue.Create("editor-response"),
                    Result = new JsonObject
                    {
                        ["ok"] = true,
                    },
                }),
            ],
            new ThrowingSpawner("not used"));

        Assert.Equal(0, exitCode);
        Assert.Empty(responses);
        Assert.Empty(stderr);
    }

    [Fact]
    public async Task RunAsync_ReadFailure_ReportsFatalAndReturnsOne()
    {
        using var stdin = new ThrowingReadStream();
        using var stdout = new MemoryStream();
        using var stderrWriter = new StringWriter();
        using var proxy = new AcpProxy("claude", stdout, stderrWriter, agentSpawner: new ThrowingSpawner("not used"));

        var exitCode = await proxy.RunAsync(stdin, CancellationToken.None);

        Assert.Equal(1, exitCode);
        Assert.Contains("Fatal error", stderrWriter.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_PreCanceledToken_CompletesWithoutFailure()
    {
        using var stdin = new MemoryStream();
        using var stdout = new MemoryStream();
        using var stderrWriter = new StringWriter();
        using var proxy = new AcpProxy("claude", stdout, stderrWriter, agentSpawner: new ThrowingSpawner("not used"));
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        var exitCode = await proxy.RunAsync(stdin, cancellation.Token);

        Assert.Equal(0, exitCode);
        Assert.DoesNotContain("Fatal error", stderrWriter.ToString(), StringComparison.Ordinal);
    }

    private static async Task<(int ExitCode, List<JsonRpcMessage> Responses, string Stderr)> RunProxyAsync(
        IReadOnlyList<string> lines,
        IAgentSpawner spawner)
    {
        var stdinPayload = string.Join('\n', lines) + '\n';
        using var stdin = new MemoryStream(Encoding.UTF8.GetBytes(stdinPayload));
        using var stdout = new MemoryStream();
        using var stderrWriter = new StringWriter();
        using var proxy = new AcpProxy("claude", stdout, stderrWriter, agentSpawner: spawner);

        var exitCode = await proxy.RunAsync(stdin, CancellationToken.None);

        var outputLines = Encoding.UTF8
            .GetString(stdout.ToArray())
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var responses = new List<JsonRpcMessage>(outputLines.Length);
        foreach (var line in outputLines)
        {
            var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcMessage);
            Assert.NotNull(message);
            responses.Add(message);
        }

        return (exitCode, responses, stderrWriter.ToString());
    }

    private static string ToLine(JsonRpcMessage message)
        => JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);

    private sealed class ThrowingSpawner(string message) : IAgentSpawner
    {
        public System.Diagnostics.Process SpawnAgent(AcpSession session, string agent)
        {
            _ = session;
            _ = agent;
            throw new InvalidOperationException(message);
        }
    }

    private sealed class ThrowingReadStream : Stream
    {
        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => 0;

        public override long Position
        {
            get => 0;
            set => throw new NotSupportedException();
        }

        public override void Flush()
        {
        }

        public override int Read(byte[] buffer, int offset, int count)
            => throw new IOException("synthetic read failure");

        public override long Seek(long offset, SeekOrigin origin)
            => throw new NotSupportedException();

        public override void SetLength(long value)
            => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count)
            => throw new NotSupportedException();

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
            => ValueTask.FromException<int>(new IOException("synthetic read failure"));
    }
}
