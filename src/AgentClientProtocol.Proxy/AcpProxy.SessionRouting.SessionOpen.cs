using System.Text.Json;
using AgentClientProtocol.Proxy.PathTranslation;
using AgentClientProtocol.Proxy.Protocol;
using AgentClientProtocol.Proxy.Sessions;

namespace AgentClientProtocol.Proxy;

public sealed partial class AcpProxy
{
    private async Task HandleInitializeAsync(JsonRpcEnvelope message)
    {
        var initializeParams = DeserializeElement(message.Params, AcpJsonContext.Default.InitializeRequestParams) ?? new InitializeRequestParams();
        cachedInitializeParams = initializeParams;
        var requestedVersion = initializeParams.ProtocolVersion ?? "2025-01-01";

        var response = new JsonRpcEnvelope
        {
            Id = message.Id,
            Result = SerializeElement(
                new InitializeResultPayload
                {
                    ProtocolVersion = requestedVersion,
                    Capabilities = new ProxyCapabilities { MultiSession = true },
                    ServerInfo = new ProxyServerInfo
                    {
                        Name = "containai-acp-proxy",
                        Version = "0.1.0",
                    },
                },
                AcpJsonContext.Default.InitializeResultPayload),
        };

        if (message.Id != null)
        {
            await output.EnqueueAsync(response).ConfigureAwait(false);
        }
    }

    private async Task HandleSessionNewAsync(JsonRpcEnvelope message)
    {
        var sessionNewInput = DeserializeElement(message.Params, AcpJsonContext.Default.SessionNewRequestParams) ?? new SessionNewRequestParams();
        var cwd = sessionNewInput.Cwd;
        var mcpServersNode = sessionNewInput.McpServers;
        var originalCwd = cwd ?? Directory.GetCurrentDirectory();

        var workspace = await WorkspaceResolver.ResolveAsync(originalCwd, cts.Token).ConfigureAwait(false);
        var session = new AcpSession(workspace);

        try
        {
            var pathTranslator = new PathTranslator(workspace);
            await agentSpawner.SpawnAgentAsync(session, agent, cts.Token).ConfigureAwait(false);
            session.ReaderTask = Task.Run(() => ReadAgentOutputLoopAsync(session));

            var initParams = new InitializeRequestParams
            {
                ProtocolVersion = cachedInitializeParams?.ProtocolVersion ?? "2025-01-01",
                ClientInfo = cachedInitializeParams?.ClientInfo,
                Capabilities = cachedInitializeParams?.Capabilities,
            };
            MergeExtensionData(initParams.ExtensionData, cachedInitializeParams?.ExtensionData);

            var initRequestId = "init-" + session.ProxySessionId;
            var initRequest = new JsonRpcEnvelope
            {
                Id = JsonRpcId.FromString(initRequestId),
                Method = "initialize",
                Params = SerializeElement(initParams, AcpJsonContext.Default.InitializeRequestParams),
            };

            var initResponse = await session.SendAndWaitForResponseAsync(initRequest, initRequestId, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
            if (initResponse == null)
            {
                throw new TimeoutException("Agent did not respond to initialize");
            }

            if (initResponse.Error != null)
            {
                var errMsg = initResponse.Error.Message ?? "Unknown error";
                throw new InvalidOperationException($"Agent initialize failed: {errMsg}");
            }

            var containerCwd = pathTranslator.TranslateToContainer(originalCwd);
            var sessionNewParams = new SessionNewRequestParams
            {
                Cwd = containerCwd,
            };
            MergeExtensionData(sessionNewParams.ExtensionData, sessionNewInput.ExtensionData);

            if (mcpServersNode is { } mcpServersValue)
            {
                var translatedMcp = pathTranslator.TranslateMcpServers(mcpServersValue.Element);
                sessionNewParams.McpServers = translatedMcp;
            }

            var sessionNewRequestId = "session-new-" + session.ProxySessionId;
            var sessionNewRequest = new JsonRpcEnvelope
            {
                Id = JsonRpcId.FromString(sessionNewRequestId),
                Method = "session/new",
                Params = SerializeElement(sessionNewParams, AcpJsonContext.Default.SessionNewRequestParams),
            };

            var sessionNewResponse = await session.SendAndWaitForResponseAsync(sessionNewRequest, sessionNewRequestId, TimeSpan.FromSeconds(30)).ConfigureAwait(false);
            if (sessionNewResponse == null)
            {
                throw new TimeoutException("Agent did not respond to session/new");
            }

            if (sessionNewResponse.Error != null)
            {
                var errMsg = sessionNewResponse.Error.Message ?? "Unknown error";
                throw new InvalidOperationException($"Agent session/new failed: {errMsg}");
            }

            var sessionNewResult = DeserializeElement(sessionNewResponse.Result, AcpJsonContext.Default.SessionNewResponsePayload);
            session.AgentSessionId = sessionNewResult?.SessionId ?? string.Empty;
            if (string.IsNullOrEmpty(session.AgentSessionId))
            {
                throw new InvalidOperationException("Agent did not return a session ID");
            }

            sessions[session.ProxySessionId] = session;

            var responsePayload = new SessionNewResponsePayload
            {
                SessionId = session.ProxySessionId,
            };
            MergeExtensionData(responsePayload.ExtensionData, sessionNewResult?.ExtensionData);
            CopySessionNewExtensions(sessionNewResponse.Result, responsePayload.ExtensionData);

            var response = new JsonRpcEnvelope
            {
                Id = message.Id,
                Result = SerializeElement(responsePayload, AcpJsonContext.Default.SessionNewResponsePayload),
            };
            if (message.Id != null)
            {
                await output.EnqueueAsync(response).ConfigureAwait(false);
            }
        }
        catch (Exception ex) when (ex is InvalidOperationException or TimeoutException or JsonException or IOException)
        {
            session.Dispose();

            if (message.Id != null)
            {
                await output.EnqueueAsync(JsonRpcHelpers.CreateErrorResponse(
                    message.Id,
                    JsonRpcErrorCodes.SessionCreationFailed,
                    $"Failed to create session: {ex.Message}")).ConfigureAwait(false);
            }
        }
    }
}
