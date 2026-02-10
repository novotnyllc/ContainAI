using System;
using System.IO;
using System.Text.Json;

namespace AgentClientProtocol.Proxy.PathTranslation;

internal sealed class McpServersPathTranslator
{
    private readonly Func<string, string> translateToContainer;

    public McpServersPathTranslator(Func<string, string> translateToContainer)
        => this.translateToContainer = translateToContainer;

    public JsonElement Translate(JsonElement mcpServersElement)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            switch (mcpServersElement.ValueKind)
            {
                case JsonValueKind.Object:
                    WriteObjectFormat(writer, mcpServersElement);
                    break;
                case JsonValueKind.Array:
                    WriteArrayFormat(writer, mcpServersElement);
                    break;
                default:
                    mcpServersElement.WriteTo(writer);
                    break;
            }
        }

        using var document = JsonDocument.Parse(stream.ToArray());
        return document.RootElement.Clone();
    }

    private void WriteObjectFormat(Utf8JsonWriter writer, JsonElement mcpServersElement)
    {
        writer.WriteStartObject();

        foreach (var property in mcpServersElement.EnumerateObject())
        {
            writer.WritePropertyName(property.Name);
            if (property.Value.ValueKind == JsonValueKind.Object)
            {
                WriteServerObject(writer, property.Value);
                continue;
            }

            property.Value.WriteTo(writer);
        }

        writer.WriteEndObject();
    }

    private void WriteArrayFormat(Utf8JsonWriter writer, JsonElement mcpServersElement)
    {
        writer.WriteStartArray();

        foreach (var serverConfig in mcpServersElement.EnumerateArray())
        {
            if (serverConfig.ValueKind == JsonValueKind.Object)
            {
                WriteServerObject(writer, serverConfig);
                continue;
            }

            serverConfig.WriteTo(writer);
        }

        writer.WriteEndArray();
    }

    private void WriteServerObject(Utf8JsonWriter writer, JsonElement serverObject)
    {
        writer.WriteStartObject();

        foreach (var property in serverObject.EnumerateObject())
        {
            if (property.NameEquals("args") && property.Value.ValueKind == JsonValueKind.Array)
            {
                writer.WritePropertyName(property.Name);
                WriteArgsArray(writer, property.Value);
                continue;
            }

            property.WriteTo(writer);
        }

        writer.WriteEndObject();
    }

    private void WriteArgsArray(Utf8JsonWriter writer, JsonElement argsArray)
    {
        writer.WriteStartArray();

        foreach (var arg in argsArray.EnumerateArray())
        {
            if (arg.ValueKind == JsonValueKind.String)
            {
                writer.WriteStringValue(translateToContainer(arg.GetString() ?? string.Empty));
                continue;
            }

            arg.WriteTo(writer);
        }

        writer.WriteEndArray();
    }
}
