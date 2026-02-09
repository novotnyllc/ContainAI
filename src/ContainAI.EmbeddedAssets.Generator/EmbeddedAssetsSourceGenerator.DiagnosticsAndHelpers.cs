using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace ContainAI.EmbeddedAssets.Generator;

public sealed partial class EmbeddedAssetsSourceGenerator
{
    private static bool ShouldIgnoreResxParsingException(Exception ex)
        => ex is XmlException or InvalidOperationException;

    private static Dictionary<string, string> BuildAdditionalFileMap(ImmutableArray<AdditionalFileContent> additionalFiles)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var additionalFile in additionalFiles)
        {
            if (string.IsNullOrWhiteSpace(additionalFile.Path))
            {
                continue;
            }

            var fullPath = NormalizePath(additionalFile.Path);
            if (string.IsNullOrWhiteSpace(fullPath))
            {
                continue;
            }

            map[fullPath] = additionalFile.Content;
        }

        return map;
    }

    private static string ResolveValue(
        string resxPath,
        XElement dataElement,
        Dictionary<string, string> additionalFileMap)
    {
        var value = dataElement.Element("value")?.Value ?? string.Empty;
        var type = dataElement.Attribute("type")?.Value;
        if (string.IsNullOrWhiteSpace(type) ||
            !type.Contains("ResXFileRef", StringComparison.Ordinal))
        {
            return value;
        }

        var separatorIndex = value.IndexOf(';');
        var fileRefPath = separatorIndex >= 0 ? value.Substring(0, separatorIndex) : value;
        if (string.IsNullOrWhiteSpace(fileRefPath))
        {
            return string.Empty;
        }

        var baseDirectory = Path.GetDirectoryName(resxPath);
        var normalizedPath = fileRefPath.Replace('\\', Path.DirectorySeparatorChar).Replace('/', Path.DirectorySeparatorChar);
        var fullPath = NormalizePath(Path.Combine(baseDirectory ?? string.Empty, normalizedPath));
        if (string.IsNullOrWhiteSpace(fullPath))
        {
            return string.Empty;
        }

        if (additionalFileMap.TryGetValue(fullPath, out var linkedValue))
        {
            return linkedValue;
        }

        return string.Empty;
    }

    private static string NormalizePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }

        try
        {
            return Path.GetFullPath(path);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return string.Empty;
        }
    }

    private static string ToStringLiteral(string value)
    {
        var builder = new StringBuilder(value.Length + 16);
        builder.Append('"');

        foreach (var character in value)
        {
            _ = character switch
            {
                '"' => builder.Append("\\\""),
                '\\' => builder.Append("\\\\"),
                '\0' => builder.Append("\\0"),
                '\a' => builder.Append("\\a"),
                '\b' => builder.Append("\\b"),
                '\f' => builder.Append("\\f"),
                '\n' => builder.Append("\\n"),
                '\r' => builder.Append("\\r"),
                '\t' => builder.Append("\\t"),
                '\v' => builder.Append("\\v"),
                _ => builder.Append(character),
            };
        }

        builder.Append('"');
        return builder.ToString();
    }
}
