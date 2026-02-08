// Path translation between host and container paths
using System.Text.Json;

namespace AgentClientProtocol.Proxy.PathTranslation;

/// <summary>
/// Translates paths between host workspace and container workspace.
/// </summary>
public sealed class PathTranslator
{
    private readonly string hostWorkspace;
    private readonly string containerWorkspace;
    private readonly string normalizedHostWorkspace;

    /// <summary>
    /// Creates a new path translator.
    /// </summary>
    /// <param name="hostWorkspacePath">The host workspace path.</param>
    /// <param name="containerWorkspacePath">The container workspace path (default: /home/agent/workspace).</param>
    public PathTranslator(string hostWorkspacePath, string containerWorkspacePath = "/home/agent/workspace")
    {
        hostWorkspace = hostWorkspacePath;
        containerWorkspace = containerWorkspacePath;
        normalizedHostWorkspace = Path.GetFullPath(hostWorkspacePath).TrimEnd(Path.DirectorySeparatorChar);
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
        catch (SystemException ex) when (ex is NotSupportedException or PathTooLongException)
        {
            _ = ex;
            return hostPath; // Invalid path format
        }

        // Exact match
        if (normalizedPath == normalizedHostWorkspace)
            return containerWorkspace;

        // Descendant match
        var prefix = normalizedHostWorkspace + Path.DirectorySeparatorChar;
        if (normalizedPath.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedPath.Substring(prefix.Length);
            return containerWorkspace + "/" + relative.Replace(Path.DirectorySeparatorChar, '/');
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
        if (normalizedContainer == containerWorkspace)
            return hostWorkspace;

        // Descendant match
        var prefix = containerWorkspace + "/";
        if (normalizedContainer.StartsWith(prefix, StringComparison.Ordinal))
        {
            var relative = normalizedContainer.Substring(prefix.Length);
            return Path.Combine(hostWorkspace, relative.Replace('/', Path.DirectorySeparatorChar));
        }

        // Not a workspace path
        return containerPath;
    }

    /// <summary>
    /// Translates MCP servers configuration, handling both object and array formats.
    /// Object format: { "server-name": { "command": "...", "args": [...] } }
    /// Array format: [ { "name": "...", "command": "...", "args": [...] } ]
    /// </summary>
    public JsonElement TranslateMcpServers(JsonElement mcpServersElement)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            switch (mcpServersElement.ValueKind)
            {
                case JsonValueKind.Object:
                    WriteTranslatedObjectFormat(writer, mcpServersElement);
                    break;
                case JsonValueKind.Array:
                    WriteTranslatedArrayFormat(writer, mcpServersElement);
                    break;
                default:
                    mcpServersElement.WriteTo(writer);
                    break;
            }
        }

        using var document = JsonDocument.Parse(stream.ToArray());
        return document.RootElement.Clone();
    }

    private void WriteTranslatedObjectFormat(Utf8JsonWriter writer, JsonElement mcpServersElement)
    {
        writer.WriteStartObject();

        foreach (var property in mcpServersElement.EnumerateObject())
        {
            writer.WritePropertyName(property.Name);
            if (property.Value.ValueKind == JsonValueKind.Object)
            {
                WriteTranslatedServerObject(writer, property.Value);
                continue;
            }

            property.Value.WriteTo(writer);
        }

        writer.WriteEndObject();
    }

    private void WriteTranslatedArrayFormat(Utf8JsonWriter writer, JsonElement mcpServersElement)
    {
        writer.WriteStartArray();

        foreach (var serverConfig in mcpServersElement.EnumerateArray())
        {
            if (serverConfig.ValueKind == JsonValueKind.Object)
            {
                WriteTranslatedServerObject(writer, serverConfig);
                continue;
            }

            serverConfig.WriteTo(writer);
        }

        writer.WriteEndArray();
    }

    private void WriteTranslatedServerObject(Utf8JsonWriter writer, JsonElement serverObject)
    {
        writer.WriteStartObject();

        foreach (var property in serverObject.EnumerateObject())
        {
            if (property.NameEquals("args") && property.Value.ValueKind == JsonValueKind.Array)
            {
                writer.WritePropertyName(property.Name);
                WriteTranslatedArgsArray(writer, property.Value);
                continue;
            }

            property.WriteTo(writer);
        }

        writer.WriteEndObject();
    }

    private void WriteTranslatedArgsArray(Utf8JsonWriter writer, JsonElement argsArray)
    {
        writer.WriteStartArray();

        foreach (var arg in argsArray.EnumerateArray())
        {
            if (arg.ValueKind == JsonValueKind.String)
            {
                writer.WriteStringValue(TranslateToContainer(arg.GetString() ?? string.Empty));
                continue;
            }

            arg.WriteTo(writer);
        }

        writer.WriteEndArray();
    }
}
