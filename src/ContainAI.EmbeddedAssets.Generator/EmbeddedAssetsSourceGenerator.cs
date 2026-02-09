using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml.Linq;
using System.Xml;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;

namespace ContainAI.EmbeddedAssets.Generator;

[Generator]
public sealed class EmbeddedAssetsSourceGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var additionalFileContents = context.AdditionalTextsProvider
            .Select(static (file, cancellationToken) => new AdditionalFileContent(
                file.Path ?? string.Empty,
                file.GetText(cancellationToken)?.ToString() ?? string.Empty))
            .Collect();

        var parsedResxFiles = context.AdditionalTextsProvider
            .Where(static file => file.Path.EndsWith(".resx", StringComparison.OrdinalIgnoreCase))
            .Combine(additionalFileContents)
            .Select(static (tuple, cancellationToken) => ParseResxFile(tuple.Left, tuple.Right, cancellationToken))
            .Where(static parsed => !parsed.Entries.IsDefaultOrEmpty)
            .Collect();

        context.RegisterSourceOutput(parsedResxFiles, static (productionContext, parsedResxFiles) =>
        {
            if (parsedResxFiles.IsDefaultOrEmpty)
            {
                return;
            }

            var allEntries = new SortedDictionary<string, string>(StringComparer.Ordinal);
            foreach (var parsedResxFile in parsedResxFiles.OrderBy(static parsed => parsed.Path, StringComparer.Ordinal))
            {
                foreach (var entry in parsedResxFile.Entries)
                {
                    allEntries[entry.Key] = entry.Value;
                }
            }

            if (allEntries.Count == 0)
            {
                return;
            }

            var source = RenderSource(allEntries);
            productionContext.AddSource("BuiltInAssets.g.cs", SourceText.From(source, Encoding.UTF8));
        });
    }

    private static ParsedResxFile ParseResxFile(
        AdditionalText file,
        ImmutableArray<AdditionalFileContent> additionalFiles,
        CancellationToken cancellationToken)
    {
        var filePath = file.Path ?? string.Empty;
        var content = file.GetText(cancellationToken)?.ToString();
        if (string.IsNullOrWhiteSpace(content))
        {
            return ParsedResxFile.Empty(filePath);
        }

        var additionalFileMap = BuildAdditionalFileMap(additionalFiles);

        try
        {
            var document = XDocument.Parse(content);
            var root = document.Root;
            if (root is null)
            {
                return ParsedResxFile.Empty(filePath);
            }

            var entries = ImmutableArray.CreateBuilder<AssetEntry>();
            foreach (var dataElement in root.Elements("data"))
            {
                var keyValue = dataElement.Attribute("name")?.Value;
                if (string.IsNullOrEmpty(keyValue))
                {
                    continue;
                }

                var value = ResolveValue(filePath, dataElement, additionalFileMap);
                entries.Add(new AssetEntry(keyValue!, value ?? string.Empty));
            }

            return new ParsedResxFile(filePath, entries.ToImmutable());
        }
        catch (XmlException)
        {
            return ParsedResxFile.Empty(filePath);
        }
        catch (InvalidOperationException)
        {
            return ParsedResxFile.Empty(filePath);
        }
    }

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

    private static string RenderSource(SortedDictionary<string, string> allEntries)
    {
        var builder = new StringBuilder();
        builder.AppendLine("// <auto-generated />");
        builder.AppendLine("#nullable enable");
        builder.AppendLine("using System;");
        builder.AppendLine("using System.Collections.Frozen;");
        builder.AppendLine("using System.Collections.Generic;");
        builder.AppendLine();
        builder.AppendLine("namespace ContainAI.Cli.Host;");
        builder.AppendLine();
        builder.AppendLine("public static class BuiltInAssets");
        builder.AppendLine("{");
        builder.AppendLine("    private static readonly FrozenDictionary<string, string> Assets = new Dictionary<string, string>(StringComparer.Ordinal)");
        builder.AppendLine("    {");

        foreach (var entry in allEntries)
        {
            builder
                .Append("        [")
                .Append(ToStringLiteral(entry.Key))
                .Append("] = ")
                .Append(ToStringLiteral(entry.Value))
                .AppendLine(",");
        }

        builder.AppendLine("    }.ToFrozenDictionary(StringComparer.Ordinal);");
        builder.AppendLine();
        builder.AppendLine("    public static IReadOnlyDictionary<string, string> All => Assets;");
        builder.AppendLine();
        builder.AppendLine("    public static bool TryGet(string key, out string value)");
        builder.AppendLine("    {");
        builder.AppendLine("        if (Assets.TryGetValue(key, out var content))");
        builder.AppendLine("        {");
        builder.AppendLine("            value = content;");
        builder.AppendLine("            return true;");
        builder.AppendLine("        }");
        builder.AppendLine();
        builder.AppendLine("        value = string.Empty;");
        builder.AppendLine("        return false;");
        builder.AppendLine("    }");
        builder.AppendLine();
        builder.AppendLine("    public static IEnumerable<(string Name, string Content)> EnumerateByPrefix(string prefix)");
        builder.AppendLine("    {");
        builder.AppendLine("        prefix ??= string.Empty;");
        builder.AppendLine();
        builder.AppendLine("        foreach (var asset in Assets)");
        builder.AppendLine("        {");
        builder.AppendLine("            if (!asset.Key.StartsWith(prefix, StringComparison.Ordinal))");
        builder.AppendLine("            {");
        builder.AppendLine("                continue;");
        builder.AppendLine("            }");
        builder.AppendLine();
        builder.AppendLine("            yield return (asset.Key[prefix.Length..], asset.Value);");
        builder.AppendLine("        }");
        builder.AppendLine("    }");
        builder.AppendLine("}");
        return builder.ToString();
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

    private readonly struct AssetEntry
    {
        public AssetEntry(string key, string value)
        {
            Key = key;
            Value = value;
        }

        public string Key { get; }

        public string Value { get; }
    }

    private readonly struct ParsedResxFile
    {
        public ParsedResxFile(string path, ImmutableArray<AssetEntry> entries)
        {
            Path = path;
            Entries = entries;
        }

        public string Path { get; }

        public ImmutableArray<AssetEntry> Entries { get; }

        public static ParsedResxFile Empty(string path) => new(path, []);
    }

    private readonly struct AdditionalFileContent
    {
        public AdditionalFileContent(string path, string content)
        {
            Path = path;
            Content = content;
        }

        public string Path { get; }

        public string Content { get; }
    }
}
