// Path translation between host and container paths
using System.Text.Json.Nodes;

namespace AgentClientProtocol.Proxy.PathTranslation;

/// <summary>
/// Translates paths between host workspace and container workspace.
/// </summary>
public sealed class PathTranslator
{
    private readonly string _hostWorkspace;
    private readonly string _containerWorkspace;
    private readonly string _normalizedHostWorkspace;

    /// <summary>
    /// Creates a new path translator.
    /// </summary>
    /// <param name="hostWorkspace">The host workspace path.</param>
    /// <param name="containerWorkspace">The container workspace path (default: /home/agent/workspace).</param>
    public PathTranslator(string hostWorkspace, string containerWorkspace = "/home/agent/workspace")
    {
        _hostWorkspace = hostWorkspace;
        _containerWorkspace = containerWorkspace;
        _normalizedHostWorkspace = Path.GetFullPath(hostWorkspace).TrimEnd(Path.DirectorySeparatorChar);
    }

    /// <summary>
    /// Translates a host path to a container path.
    /// </summary>
    /// <param name="hostPath">The host path to translate.</param>
    /// <returns>The container path, or the original path if not under the workspace.</returns>
    public string TranslateToContainer(string hostPath)
    {
        ArgumentNullException.ThrowIfNull(hostPath);

        // Only translate absolute paths
        if (!Path.IsPathRooted(hostPath))
            return hostPath;

        // Normalize the path
        string normalizedPath;
        try
        {
            normalizedPath = Path.GetFullPath(hostPath).TrimEnd(Path.DirectorySeparatorChar);
        }
        catch (ArgumentException)
        {
            return hostPath; // Invalid path format
        }
        catch (NotSupportedException)
        {
            return hostPath; // Invalid path format
        }
        catch (PathTooLongException)
        {
            return hostPath; // Invalid path format
        }

        // Exact match
        if (normalizedPath == _normalizedHostWorkspace)
            return _containerWorkspace;

        // Descendant match
        var prefix = _normalizedHostWorkspace + Path.DirectorySeparatorChar;
        if (normalizedPath.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedPath.Substring(prefix.Length);
            return _containerWorkspace + "/" + relative.Replace(Path.DirectorySeparatorChar, '/');
        }

        // Not a workspace path
        return hostPath;
    }

    /// <summary>
    /// Translates a container path back to a host path.
    /// </summary>
    /// <param name="containerPath">The container path to translate.</param>
    /// <returns>The host path, or the original path if not under the workspace.</returns>
    public string TranslateToHost(string containerPath)
    {
        ArgumentNullException.ThrowIfNull(containerPath);

        // Only translate absolute paths
        if (!containerPath.StartsWith('/'))
            return containerPath;

        // Normalize container path
        var normalizedContainer = containerPath.TrimEnd('/');

        // Exact match
        if (normalizedContainer == _containerWorkspace)
            return _hostWorkspace;

        // Descendant match
        var prefix = _containerWorkspace + "/";
        if (normalizedContainer.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedContainer.Substring(prefix.Length);
            return Path.Combine(_hostWorkspace, relative.Replace('/', Path.DirectorySeparatorChar));
        }

        // Not a workspace path
        return containerPath;
    }

    /// <summary>
    /// Translates MCP servers configuration, handling both object and array formats.
    /// Object format: { "server-name": { "command": "...", "args": [...] } }
    /// Array format: [ { "name": "...", "command": "...", "args": [...] } ]
    /// </summary>
    public JsonNode TranslateMcpServers(JsonNode mcpServersNode)
    {
        ArgumentNullException.ThrowIfNull(mcpServersNode);

        if (mcpServersNode is JsonObject mcpObj)
        {
            return TranslateMcpServersObject(mcpObj);
        }
        else if (mcpServersNode is JsonArray mcpArray)
        {
            return TranslateMcpServersArray(mcpArray);
        }
        // Unknown format - pass through unchanged
        return mcpServersNode.DeepClone();
    }

    private JsonArray TranslateMcpServersArray(JsonArray mcpServers)
    {
        var result = new JsonArray();

        foreach (var serverConfig in mcpServers)
        {
            if (serverConfig is not JsonObject serverObj)
            {
                result.Add(serverConfig?.DeepClone());
                continue;
            }

            var translatedServer = new JsonObject();

            foreach (var (key, value) in serverObj)
            {
                if (key == "args" && value is JsonArray argsArray)
                {
                    translatedServer[key] = TranslateArgsArray(argsArray);
                }
                else
                {
                    translatedServer[key] = value?.DeepClone();
                }
            }

            // Cast to JsonNode to avoid generic Add<T> warnings with AOT
            result.Add((JsonNode)translatedServer);
        }

        return result;
    }

    private JsonObject TranslateMcpServersObject(JsonObject mcpServers)
    {
        var result = new JsonObject();

        foreach (var (serverName, serverConfig) in mcpServers)
        {
            if (serverConfig is not JsonObject serverObj)
            {
                result[serverName] = serverConfig?.DeepClone();
                continue;
            }

            var translatedServer = new JsonObject();

            foreach (var (key, value) in serverObj)
            {
                if (key == "args" && value is JsonArray argsArray)
                {
                    translatedServer[key] = TranslateArgsArray(argsArray);
                }
                else
                {
                    translatedServer[key] = value?.DeepClone();
                }
            }

            result[serverName] = translatedServer;
        }

        return result;
    }

    private JsonArray TranslateArgsArray(JsonArray argsArray)
    {
        var translatedArgs = new JsonArray();
        foreach (var arg in argsArray)
        {
            if (arg is JsonValue argValue && argValue.TryGetValue<string>(out var argStr))
            {
                // Cast to JsonNode to avoid generic Add<T> warnings with AOT
                translatedArgs.Add((JsonNode)JsonValue.Create(TranslateToContainer(argStr))!);
            }
            else
            {
                translatedArgs.Add(arg?.DeepClone());
            }
        }
        return translatedArgs;
    }
}
