using System.IO.Pipelines;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;
using Xunit;

namespace AgentClientProtocol.Proxy.Tests;

public sealed class AcpProxyLifecycleTests
{
    [Fact]
    public async Task RunAsync_FullSessionLifecycle_RoutesRequestsAndTranslatesSessionIds()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.Success);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("editor-init"),
            Method = "initialize",
            Params = new JsonObject
            {
                ["protocolVersion"] = "2025-01-01",
                ["clientInfo"] = new JsonObject { ["name"] = "editor" },
                ["capabilities"] = new JsonObject { ["streaming"] = true },
                ["customInitializeFlag"] = "enabled",
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
                ["customSessionField"] = "present",
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
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.InitializeError);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

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
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.MissingSessionId);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

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
    public async Task RunAsync_SessionNew_WhenAgentDoesNotRespondToInitialize_ReturnsSessionCreationError()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.NoInitializeResponse);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-init-timeout"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-init-timeout", response.Id?.GetValue<string>());
        Assert.Equal(JsonRpcErrorCodes.SessionCreationFailed, response.Error?.Code);
        Assert.Contains("did not respond to initialize", response.Error?.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_SessionNew_WhenAgentDoesNotRespondToSessionNew_ReturnsSessionCreationError()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.NoSessionNewResponse);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-session-timeout"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-session-timeout", response.Id?.GetValue<string>());
        Assert.Equal(JsonRpcErrorCodes.SessionCreationFailed, response.Error?.Code);
        Assert.Contains("did not respond to session/new", response.Error?.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_WhenInputEndsWithActiveSession_ShutsDownSessionGracefully()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.Success);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

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
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.MalformedPromptOutput);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

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

    [Fact]
    public async Task RunAsync_SessionNew_WhenCachedInitializeMissingVersion_UsesDefaultProtocolVersion()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.Success);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("init-default-version"),
            Method = "initialize",
            Params = new JsonObject(),
        });
        _ = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-default-version"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-default-version", response.Id?.GetValue<string>());
        Assert.NotNull(response.Result?["sessionId"]);

        await harness.CompleteInputAsync();
        _ = await harness.WaitForExitAsync(TestContext.Current.CancellationToken);

        var transcript = await spawner.ReadTranscriptLinesAsync(TestContext.Current.CancellationToken);
        var forwardedInitialize = transcript.Single(line => line.Contains("\"method\":\"initialize\"", StringComparison.Ordinal));
        Assert.Contains("\"protocolVersion\":\"2025-01-01\"", forwardedInitialize, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_SessionNew_WhenAgentSessionNewErrorMissingMessage_ReturnsUnknownError()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.SessionNewErrorWithoutMessage);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-error"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("new-error", response.Id?.GetValue<string>());
        Assert.Equal(JsonRpcErrorCodes.SessionCreationFailed, response.Error?.Code);
        Assert.Contains("Unknown error", response.Error?.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RunAsync_SessionPrompt_WhenAgentEmitsBlankAndNullLines_ContinuesProcessing()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.PromptOutputIncludesBlankAndNull);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-blank-null"),
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
            Id = JsonValue.Create("prompt-blank-null"),
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
            if (message.Id?.GetValue<string>() == "prompt-blank-null")
            {
                promptResponse = message;
            }
        }

        Assert.NotNull(promptResponse);
        Assert.NotNull(promptResponse.Result);
    }

    [Fact]
    public async Task RunAsync_SessionEnd_WhenAgentDoesNotExit_StillAcknowledgesAfterTimeout()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.SlowSessionEnd);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-slow-end"),
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
            Id = JsonValue.Create("end-slow"),
            Method = "session/end",
            Params = new JsonObject
            {
                ["sessionId"] = proxySessionId,
            },
        });

        var endResponse = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.Equal("end-slow", endResponse.Id?.GetValue<string>());
        Assert.NotNull(endResponse.Result);
    }

    [Fact]
    public async Task RunAsync_Shutdown_WhenAgentDoesNotExit_CompletesAfterTimeout()
    {
        var spawner = new ScriptedAgentSpawner(ScriptedAgentMode.SlowSessionEnd);
        await using var spawnerScope = spawner.ConfigureAwait(false);
        var harness = await ProxyHarness.StartAsync(spawner, TestContext.Current.CancellationToken).ConfigureAwait(true);
        await using var harnessScope = harness.ConfigureAwait(false);

        await harness.WriteAsync(new JsonRpcMessage
        {
            Id = JsonValue.Create("new-shutdown-slow"),
            Method = "session/new",
            Params = new JsonObject
            {
                ["cwd"] = Directory.GetCurrentDirectory(),
            },
        });

        var response = await harness.ReadMessageAsync(TestContext.Current.CancellationToken);
        Assert.NotNull(response.Result?["sessionId"]);

        await harness.CompleteInputAsync();
        var exitCode = await harness.WaitForExitAsync(TestContext.Current.CancellationToken);
        Assert.Equal(0, exitCode);
    }

    private enum ScriptedAgentMode
    {
        Success,
        InitializeError,
        NoInitializeResponse,
        MissingSessionId,
        NoSessionNewResponse,
        MalformedPromptOutput,
        SessionNewErrorWithoutMessage,
        PromptOutputIncludesBlankAndNull,
        SlowSessionEnd,
    }

    private sealed class ScriptedAgentSpawner : IAgentSpawner, IAsyncDisposable
    {
        private readonly Lock _gate = new();
        private readonly List<string> _transcript = [];
        private readonly ScriptedAgentMode _mode;

        public ScriptedAgentSpawner(ScriptedAgentMode mode)
        {
            _mode = mode;
            AgentSessionId = $"agent-{Guid.NewGuid():N}";
        }

        public string AgentSessionId { get; }

        public Task SpawnAgentAsync(AcpSession session, string agent, CancellationToken cancellationToken = default)
        {
            _ = agent;
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
            var executionTask = RunScriptedAgentAsync(input.Reader, output.Writer, session.CancellationToken);
            session.AttachAgentTransport(input.Writer, output.Reader, executionTask);
            return Task.CompletedTask;
        }

        private async Task RunScriptedAgentAsync(ChannelReader<string> input, ChannelWriter<string> output, CancellationToken cancellationToken)
        {
            try
            {
                await foreach (var line in input.ReadAllAsync(cancellationToken).ConfigureAwait(false))
                {
                    lock (_gate)
                    {
                        _transcript.Add(line);
                    }

                    var message = JsonSerializer.Deserialize(line, AcpJsonContext.Default.JsonRpcMessage);
                    if (message == null || string.IsNullOrWhiteSpace(message.Method))
                    {
                        continue;
                    }

                    var requestId = JsonRpcHelpers.NormalizeId(message.Id);
                    switch (message.Method)
                    {
                        case "initialize":
                            if (_mode == ScriptedAgentMode.InitializeError)
                            {
                                await WriteMessageAsync(output, new JsonRpcMessage
                                {
                                    Id = JsonValue.Create(requestId),
                                    Error = new JsonRpcError
                                    {
                                        Code = JsonRpcErrorCodes.InternalError,
                                        Message = "initialize failed",
                                    },
                                }, cancellationToken).ConfigureAwait(false);
                            }
                            else if (_mode == ScriptedAgentMode.NoInitializeResponse)
                            {
                                return;
                            }
                            else
                            {
                                await WriteMessageAsync(output, new JsonRpcMessage
                                {
                                    Id = JsonValue.Create(requestId),
                                    Result = new JsonObject
                                    {
                                        ["capabilities"] = new JsonObject
                                        {
                                            ["ok"] = true,
                                        },
                                    },
                                }, cancellationToken).ConfigureAwait(false);
                            }
                            break;

                        case "session/new":
                            if (_mode == ScriptedAgentMode.MissingSessionId)
                            {
                                await WriteMessageAsync(output, new JsonRpcMessage
                                {
                                    Id = JsonValue.Create(requestId),
                                    Result = new JsonObject(),
                                }, cancellationToken).ConfigureAwait(false);
                            }
                            else if (_mode == ScriptedAgentMode.SessionNewErrorWithoutMessage)
                            {
                                await output.WriteAsync(
                                    $"{{\"jsonrpc\":\"2.0\",\"id\":\"{requestId}\",\"error\":{{\"code\":-32603,\"message\":null}}}}",
                                    cancellationToken).ConfigureAwait(false);
                            }
                            else if (_mode == ScriptedAgentMode.NoSessionNewResponse)
                            {
                                return;
                            }
                            else
                            {
                                await WriteMessageAsync(output, new JsonRpcMessage
                                {
                                    Id = JsonValue.Create(requestId),
                                    Result = new JsonObject
                                    {
                                        ["sessionId"] = AgentSessionId,
                                    },
                                }, cancellationToken).ConfigureAwait(false);
                            }
                            break;

                        case "session/prompt":
                            if (_mode == ScriptedAgentMode.MalformedPromptOutput)
                            {
                                await output.WriteAsync("{ this is not json }", cancellationToken).ConfigureAwait(false);
                            }
                            else if (_mode == ScriptedAgentMode.PromptOutputIncludesBlankAndNull)
                            {
                                await output.WriteAsync(string.Empty, cancellationToken).ConfigureAwait(false);
                                await output.WriteAsync("null", cancellationToken).ConfigureAwait(false);
                            }

                            await WriteMessageAsync(output, new JsonRpcMessage
                            {
                                Method = "session/progress",
                                Params = new JsonObject
                                {
                                    ["sessionId"] = AgentSessionId,
                                    ["text"] = "working",
                                },
                            }, cancellationToken).ConfigureAwait(false);

                            await WriteMessageAsync(output, new JsonRpcMessage
                            {
                                Id = JsonValue.Create(requestId),
                                Result = new JsonObject
                                {
                                    ["ok"] = true,
                                },
                            }, cancellationToken).ConfigureAwait(false);
                            break;

                        case "session/end":
                            if (_mode == ScriptedAgentMode.SlowSessionEnd)
                            {
                                await Task.Delay(TimeSpan.FromSeconds(8), cancellationToken).ConfigureAwait(false);
                            }

                            if (!string.IsNullOrWhiteSpace(requestId))
                            {
                                await WriteMessageAsync(output, new JsonRpcMessage
                                {
                                    Id = JsonValue.Create(requestId),
                                    Result = new JsonObject(),
                                }, cancellationToken).ConfigureAwait(false);
                            }

                            return;
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
            }
            finally
            {
                output.TryComplete();
            }
        }

        public Task<IReadOnlyList<string>> ReadTranscriptLinesAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (_gate)
            {
                return Task.FromResult<IReadOnlyList<string>>(_transcript.ToArray());
            }
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        private static Task WriteMessageAsync(ChannelWriter<string> output, JsonRpcMessage message, CancellationToken cancellationToken)
        {
            var payload = JsonSerializer.Serialize(message, AcpJsonContext.Default.JsonRpcMessage);
            return output.WriteAsync(payload, cancellationToken).AsTask();
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
            await _stdinWriter.WriteLineAsync(line).ConfigureAwait(false);
        }

        public async Task<JsonRpcMessage> ReadMessageAsync(CancellationToken cancellationToken)
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));

            var line = await _stdoutReader.ReadLineAsync(timeout.Token).ConfigureAwait(false);
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
            await _stdinWriter.DisposeAsync().ConfigureAwait(false);
            await _stdinPipe.Writer.CompleteAsync().ConfigureAwait(false);
        }

        public Task<int> WaitForExitAsync(CancellationToken cancellationToken)
            => _runTask.WaitAsync(cancellationToken);

        public async ValueTask DisposeAsync()
        {
            try
            {
                await CompleteInputAsync().ConfigureAwait(false);
            }
            catch (IOException ex)
            {
                System.Diagnostics.Debug.WriteLine(ex);
            }
            catch (ObjectDisposedException ex)
            {
                System.Diagnostics.Debug.WriteLine(ex);
            }
            catch (InvalidOperationException ex)
            {
                System.Diagnostics.Debug.WriteLine(ex);
            }

            _proxy.Cancel();
            _proxy.Dispose();
            _stdinReaderStream.Dispose();
            _stdoutReader.Dispose();
            _stdoutWriterStream.Dispose();
            await _stdinPipe.Reader.CompleteAsync().ConfigureAwait(false);
            await _stdoutPipe.Reader.CompleteAsync().ConfigureAwait(false);
            await _stdoutPipe.Writer.CompleteAsync().ConfigureAwait(false);
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
