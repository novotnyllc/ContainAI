// Path translation between host and container paths
using System.Text.Json;

namespace AgentClientProtocol.Proxy.PathTranslation;

/// <summary>
/// Translates paths between host workspace and container workspace.
/// </summary>
public sealed class PathTranslator
{
    private readonly WorkspacePathTranslator workspacePathTranslator;
    private readonly McpServersPathTranslator mcpServersPathTranslator;

    /// <summary>
    /// Creates a new path translator.
    /// </summary>
    /// <param name="hostWorkspacePath">The host workspace path.</param>
    /// <param name="containerWorkspacePath">The container workspace path (default: /home/agent/workspace).</param>
    public PathTranslator(string hostWorkspacePath, string containerWorkspacePath = "/home/agent/workspace")
    {
        workspacePathTranslator = new WorkspacePathTranslator(hostWorkspacePath, containerWorkspacePath);
        mcpServersPathTranslator = new McpServersPathTranslator(TranslateToContainer);
    }

    /// <summary>
    /// Translates a host path to a container path.
    /// </summary>
    /// <param name="hostPath">The host path to translate.</param>
    /// <returns>The container path, or the original path if not under the workspace.</returns>
    public string TranslateToContainer(string hostPath)
        => workspacePathTranslator.TranslateToContainer(hostPath);

    /// <summary>
    /// Translates a container path back to a host path.
    /// </summary>
    /// <param name="containerPath">The container path to translate.</param>
    /// <returns>The host path, or the original path if not under the workspace.</returns>
    public string TranslateToHost(string containerPath)
        => workspacePathTranslator.TranslateToHost(containerPath);

    /// <summary>
    /// Translates MCP servers configuration, handling both object and array formats.
    /// Object format: { "server-name": { "command": "...", "args": [...] } }
    /// Array format: [ { "name": "...", "command": "...", "args": [...] } ]
    /// </summary>
    public JsonElement TranslateMcpServers(JsonElement mcpServersElement)
        => mcpServersPathTranslator.Translate(mcpServersElement);
}
