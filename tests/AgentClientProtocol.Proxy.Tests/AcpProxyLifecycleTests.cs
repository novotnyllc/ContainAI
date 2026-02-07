using System.Diagnostics;
using System.IO.Pipelines;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpProxyLifecycleTests
{
    [Fact]
    public async Task RunAsync_FullSessionLifecycle_RoutesRequestsAndTranslatesSessionIds()
    {
        await using var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.Success);
        await using var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("editor-init"),
            Method = "initialize",
            Params = new JsonObject
            {
                ["protocolVersion"] = "2025-01-01",
                ["clientInfo"] = new JsonObject { ["name"] = "editor" },
                ["capabilities"] = new JsonObject { ["streaming"] = true },
            },
        });

        var initResponse = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("editor-init", initResponse.Id?.GetValue<string>());

        using var temp = new TempDirectory();
        var workspace = Path.Combine(temp.Path, "workspace");
        var nestedCwd = Path.Combine(workspace, "nested");
        Directory.CreateDirectory(Path.Combine(workspace, ".containai"));
        Directory.CreateDirectory(nestedCwd);
        await File.WriteAllTextAsync(
            Path.Combine(workspace, ".containai", "config.toml"),
            "workspace = \"default\"",
            TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("editor-session-new"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = nestedCwd,
                ["mcpServers"] = new JsonObject
                {
                    ["fs"] = new JsonObject
                    {
                        ["command"] = "npx",
                        ["args"] = new JsonArray(
                            "-y",
                            "@modelcontextprotocol/server-filesystem",
                            Path.Combine(workspace, "docs"))
                    },
                },
            },
        });

        var sessionNewResponse = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("editor-session-new", sessionNewResponse.Id?.GetValue<string>());
        var proxySessionId = sessionNewResponse.Result?["sessionId"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(proxySessionId));

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("editor-prompt"),
            Method = "session/prompt",
            Params = new JsonObject
            {
                ["sessionId"] = proxySessionId,
                ["prompt"] = "hello",
            },
        });

        JsonRpcMessage? promptNotification = null;
        JsonRpcMessage? promptResponse = null;
        for (var index = 0; index < 4 && (promptNotification is null || promptResponse is null); index++)
        {
            var message = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
            if (message.Method == "session/progress")
            {
                promptNotification = message;
            }

            if (message.Id?.GetValue<string>() == "editor-prompt")
            {
                promptResponse = message;
            }
        }

        Assert.NotNull(promptNotification);
        Assert.NotNull(promptResponse);
        Assert.Equal(proxySessionId, promptNotification.Params?["sessionId"]?.GetValue<string>());

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("editor-end"),
            Method = "session/end",
            Params = new JsonObject
            {
                ["sessionId"] = proxySessionId,
            },
        });

        var endResponse = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("editor-end", endResponse.Id?.GetValue<string>());
        Assert.NotNull(endResponse.Result);

        await harness.CompleteInputAsync();
        var exitCode = await harness.WaitForExitAsync(TestContext.Current.CancellationToken);
        Assert.Equal(0, exitCode);

        var transcript = await spawner.ReadTranscriptLinesAsync(TestContext.Current.CancellationToken);
        Assert.Contains(transcript, static line => line.Contains("\"method\":\"initialize\"", StringComparison.Ordinal));
        Assert.Contains(transcript, static line => line.Contains("\"method\":\"session/new\"", StringComparison.Ordinal));
        Assert.Contains(transcript, static line => line.Contains("\"method\":\"session/prompt\"", StringComparison.Ordinal));

        var forwardedPromptLine = transcript.Single(line => line.Contains("\"method\":\"session/prompt\"", StringComparison.Ordinal));
        using var forwardedPromptJson = JsonDocument.Parse(forwardedPromptLine);
        Assert.Equal(
            spawner.AgentSessionId,
            forwardedPromptJson.RootElement.GetProperty("params").GetProperty("sessionId").GetString());

        var forwardedSessionNewLine = transcript.Single(line => line.Contains("\"method\":\"session/new\"", StringComparison.Ordinal));
        using var forwardedSessionNewJson = JsonDocument.Parse(forwardedSessionNewLine);
        var forwardedCwd = forwardedSessionNewJson.RootElement.GetProperty("params").GetProperty("cwd").GetString();
        Assert.Equal("/home/agent/workspace/nested", forwardedCwd);
    }

    [Fact]
    public async Task RunAsync_SessionNew_WhenAgentInitializeFails_ReturnsSessionCreationError()
    {
        await using var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.InitializeError);
        await using var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-fail"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-fail", response.Id?.GetValue<string>());
        Assert.Equal(JsonRpcErrorCodes.SessionCreationFailed, response.Error?.Code);
        Assert.Contains("initialize failed", response.Error?.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RunAsync_SessionNew_WhenAgentOmitsSessionId_ReturnsSessionCreationError()
    {
        await using var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.MissingSessionId);
        await using var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-missing"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-missing", response.Id?.GetValue<string>());
        Assert.Equal(JsonRpcErrorCodes.SessionCreationFailed, response.Error?.Code);
        Assert.Contains("did not return a session ID", response.Error?.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_WhenInputEndsWithActiveSession_ShutsDownSessionGracefully()
    {
        await using var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.Success);
        await using var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("shutdown-new"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("shutdown-new", response.Id?.GetValue<string>());
        Assert.NotNull(response.Result?["sessionId"]);

        await harness.CompleteInputAsync();
        var exitCode = await harness.WaitForExitAsync(TestContext.Current.CancellationToken);
        Assert.Equal(0, exitCode);

        var transcript = await spawner.ReadTranscriptLinesAsync(TestContext.Current.CancellationToken);
        Assert.Contains(transcript, static line => line.Contains("\"method\":\"session/end\"", StringComparison.Ordinal));
    }

    [Fact]
    public async Task RunAsync_SessionPrompt_WhenAgentEmitsMalformedJson_ContinuesProcessing()
    {
        await using var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.MalformedPromptOutput);
        await using var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-malformed"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var sessionResponse = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        var proxySessionId = sessionResponse.Result?["sessionId"]?.GetValue<string>();
        Assert.False(string.IsNullOrWhiteSpace(proxySessionId));

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("prompt-malformed"),
            Method = "session/prompt",
            Params = new JsonObject
            {
                ["sessionId"] = proxySessionId,
                ["prompt"] = "hi",
            },
        });

        JsonRpcMessage? promptResponse = null;
        for (var index = 0; index < 4 && promptResponse is null; index++)
        {
            var message = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
            if (message.Id?.GetValue<string>() == "prompt-malformed")
            {
                promptResponse = message;
            }
        }

        Assert.NotNull(promptResponse);
        Assert.NotNull(promptResponse.Result);
    }

    private enum ScriptedAgentMode
    {
        Success,
        InitializeError,
        MissingSessionId,
        MalformedPromptOutput,
    }

    private sealed class ScriptedAgentSpawner : IAgentSpawner, IAsyncDisposable
    {
        private readonly string _tempRoot;
        private readonly string _scriptPath;
        private readonly string _transcriptPath;
        private readonly ScriptedAgentMode _mode;

        public ScriptedAgentSpawner(ScriptedAgentMode mode)
        {
            _mode = mode;
            _tempRoot = Path.Combine(Path.GetTempPath(), $"acp-agent-{Guid.NewGuid():N}");
            Directory.CreateDirectory(_tempRoot);
            _scriptPath = Path.Combine(_tempRoot, "agent.sh");
            _transcriptPath = Path.Combine(_tempRoot, "transcript.log");
            AgentSessionId = $"agent-{Guid.NewGuid():N}";

            File.WriteAllText(_scriptPath, """
#!/usr/bin/env bash
set -euo pipefail
mode="$1"
transcript="$2"
agent_session="$3"

extract_id() {
  printf '%s\n' "$1" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
}

while IFS= read -r line; do
  printf '%s\n' "$line" >> "$transcript"

  if [[ "$line" == *'"method":"initialize"'* ]]; then
    id="$(extract_id "$line")"
    if [[ "$mode" == "InitializeError" ]]; then
      printf '{"jsonrpc":"2.0","id":"%s","error":{"code":-32603,"message":"initialize failed"}}\n' "$id"
    else
      printf '{"jsonrpc":"2.0","id":"%s","result":{"capabilities":{"ok":true}}}\n' "$id"
    fi
    continue
  fi

  if [[ "$line" == *'"method":"session/new"'* ]]; then
    id="$(extract_id "$line")"
    if [[ "$mode" == "MissingSessionId" ]]; then
      printf '{"jsonrpc":"2.0","id":"%s","result":{}}\n' "$id"
    else
      printf '{"jsonrpc":"2.0","id":"%s","result":{"sessionId":"%s"}}\n' "$id" "$agent_session"
    fi
    continue
  fi

  if [[ "$line" == *'"method":"session/prompt"'* ]]; then
    id="$(extract_id "$line")"
    if [[ "$mode" == "MalformedPromptOutput" ]]; then
      printf '{ this is not json }\n'
    fi
    printf '{"jsonrpc":"2.0","method":"session/progress","params":{"sessionId":"%s","text":"working"}}\n' "$agent_session"
    printf '{"jsonrpc":"2.0","id":"%s","result":{"ok":true}}\n' "$id"
    continue
  fi

  if [[ "$line" == *'"method":"session/end"'* ]]; then
    id="$(extract_id "$line")"
    if [[ -n "$id" ]]; then
      printf '{"jsonrpc":"2.0","id":"%s","result":{}}\n' "$id"
    fi
    exit 0
  fi
done
""");
            EnsureExecutable(_scriptPath);
        }

        public string AgentSessionId { get; }

        public Process SpawnAgent(AcpSession session, string agent)
        {
            _ = session;
            _ = agent;

            var startInfo = new ProcessStartInfo("bash")
            {
                UseShellExecute = false,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            startInfo.ArgumentList.Add(_scriptPath);
            startInfo.ArgumentList.Add(_mode.ToString());
            startInfo.ArgumentList.Add(_transcriptPath);
            startInfo.ArgumentList.Add(AgentSessionId);

            return Process.Start(startInfo) ?? throw new InvalidOperationException("Failed to start scripted agent.");
        }

        public async Task<IReadOnlyList<string>> ReadTranscriptLinesAsync(CancellationToken cancellationToken)
        {
            if (!File.Exists(_transcriptPath))
            {
                return [];
            }

            return await File.ReadAllLinesAsync(_transcriptPath, cancellationToken);
        }

        public ValueTask DisposeAsync()
        {
            if (Directory.Exists(_tempRoot))
            {
                Directory.Delete(_tempRoot, recursive: true);
            }

            return ValueTask.CompletedTask;
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
    }

    private sealed class ProxyHarness : IAsyncDisposable
    {
        private readonly Pipe _stdinPipe;
        private readonly Pipe _stdoutPipe;
        private readonly Stream _stdinReaderStream;
        private readonly Stream _stdoutWriterStream;
        private readonly StreamWriter _stdinWriter;
        private readonly StreamReader _stdoutReader;
        private readonly AcpProxy _proxy;
        private readonly Task<int> _runTask;
        private bool _inputCompleted;

        private ProxyHarness(IAgentSpawner spawner)
        {
            _stdinPipe = new Pipe();
            _stdoutPipe = new Pipe();
            _stdinReaderStream = _stdinPipe.Reader.AsStream();
            _stdoutWriterStream = _stdoutPipe.Writer.AsStream();

            _stdinWriter = new StreamWriter(_stdinPipe.Writer.AsStream(), new UTF8Encoding(false))
            {
                AutoFlush = true,
            };
            _stdoutReader = new StreamReader(_stdoutPipe.Reader.AsStream(), Encoding.UTF8);

            _proxy = new AcpProxy("claude", _stdoutWriterStream, TextWriter.Null, agentSpawner: spawner);
            _runTask = _proxy.RunAsync(_stdinReaderStream, CancellationToken.None);
        }

        public static Task<ProxyHarness> StartAsync(IAgentSpawner spawner, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.FromResult(new ProxyHarness(spawner));
        }

        public async Task WriteAsync(JsonRpcMessage message)
        {
            var line = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
            await _stdinWriter.WriteLineAsync(line);
        }

        public async Task<JsonRpcMessage> ReadMessageAsync(CancellationToken cancellationToken)
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));

            var line = await _stdoutReader.ReadLineAsync(timeout.Token);
            Assert.False(string.IsNullOrWhiteSpace(line));

            var message = JsonSerializer.Deserialize(line!, AcpJsonContext.Default.JsonRpcMessage);
            return Assert.IsType<JsonRpcMessage>(message);
        }

        public async Task CompleteInputAsync()
        {
            if (_inputCompleted)
            {
                return;
            }

            _inputCompleted = true;
            await _stdinWriter.DisposeAsync();
            await _stdinPipe.Writer.CompleteAsync();
        }

        public Task<int> WaitForExitAsync(CancellationToken cancellationToken)
            => _runTask.WaitAsync(cancellationToken);

        public async ValueTask DisposeAsync()
        {
            try
            {
                await CompleteInputAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine(ex);
            }

            _proxy.Cancel();
            _proxy.Dispose();
            _stdinReaderStream.Dispose();
            _stdoutReader.Dispose();
            _stdoutWriterStream.Dispose();
            await _stdinPipe.Reader.CompleteAsync();
            await _stdoutPipe.Reader.CompleteAsync();
            await _stdoutPipe.Writer.CompleteAsync();
        }
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"acp-proxy-tests-{Guid.NewGuid():N}");
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
